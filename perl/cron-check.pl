#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use YAML;
use Try::Tiny;
use DBI;
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Time::HiRes;
use Array::Diff;
use File::Find;
our($a,$b);

sub formatted_date {
    my $time = shift || Time::HiRes::time;
    DateTime::Format::Strptime::strftime(
        '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}
sub file_info {
    my $path = shift;
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($path);
    if($dev){
        return {
            name => basename($path),
            path => $path,
            atime => $atime,
            mtime => $mtime,
            ctime => $ctime,
            size => $size,
            mode => $mode
        };
    }else{
        return {
            name => basename($path),
            path => $path,
            error => $!
        }
    }
}


my $config_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
my $config = YAML::LoadFile($config_file);
my %opts = (
    data_source => $config->{store}->{core}->{options}->{data_source},
    username => $config->{store}->{core}->{options}->{username},
    password => $config->{store}->{core}->{options}->{password}
);

my $store = Catmandu::Store::DBI->new(%opts);
my $scans = $store->bag("scans");
my $profiles = $config->{profiles} || {};
my $mount_conf = $config->{mounts}->{directories};

my $users = DBI->connect($opts{data_source}, $opts{username}, $opts{password}, {
    AutoCommit => 1,
    RaiseError => 1,
    mysql_auto_reconnect => 1
});

#stap 1: zoek scans van scanners
my $sth_each = $users->prepare("select * from users where roles like '%scanner'");
my $sth_get = $users->prepare("select * from users where id = ?");
$sth_each->execute() or die($sth_each->errstr());
while(my $user = $sth_each->fetchrow_hashref()){
    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};
    open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d | sort |" or die($!);
    while(my $dir = <CMD>){
        chomp($dir);    
        my $basename = basename($dir);
        my $scan = $scans->get($basename);
        if(!$scan){
            say "adding new record $basename";
            $scans->add({
                _id => $basename,
                name => undef,
                path => $dir,
                status => "incoming",
                status_history => [{
                    user_name => $user->{login},
                    status => "incoming",
                    datetime => Time::HiRes::time,
                    comments => ""
                }],
                check_log => [],
                files => [],
                user_id => $user->{id},
                datetime_last_modified => Time::HiRes::time,
                project_id => undef,
                metadata => [],
                comments => []
            });
        }else{
            #het kan natuurlijk ook zijn dat een andere gebruiker dezelfde map heeft verwerkt..
            if("$scan->{user_id}" eq "$user->{id}" && $scan->{status} eq "reprocess_scans"){
                say "ah you little bastard, you came back?";
                #03_reprocessing => 01_ready, maar laat de oude map in 03_reprocessing staan (verantwoordelijkheid van de scanners)

                #pas paden aan
                my $oldpath = $scan->{path};
                foreach my $file(@{ $scan->{files} }){
                    $file->{path} =~ s/^$oldpath/$dir/;
                }
                $scan->{path} = $dir;

                #update file info
                foreach my $file(@{ $scan->{files} }){
                    my $new_stats = file_info($file->{path});
                    $file->{$_} = $new_stats->{$_} foreach(keys %$new_stats);
                }

                #status op 'incoming_back'
                $scan->{status} = "incoming_back";
                push @{ $scan->{status_history} },{
                    user_name => $user->{login},
                    status => "incoming_back",
                    datetime => Time::HiRes::time,
                    comments => ""
                };

                $scans->add($scan);
            }
        }
    }
    close CMD;   
}

#stap 2: doe check
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= load_package($class)->new(%$args);
}
my @scan_ids = ();

$scans->each(sub{ 

    my $scan = shift;
    #nieuwe of slechte directories moeten sowieso opnieuw gecheckt worden
    if (
        $scan->{status} && 
        (
            $scan->{status} eq "incoming" || 
            $scan->{status} eq "incoming_error" ||
            $scan->{status} eq "incoming_back"
        )

    ){
        push @scan_ids,$scan->{_id};
    }
    #incoming_ok enkel indien er iets aan bestandslijst gewijzigd is
    elsif($scan->{status} eq "incoming_ok"){
        my $new = [];
        find({          
            wanted => sub{
            my $path = abs_path($File::Find::name);
            return if $path eq abs_path($scan->{path});
            push @$new,$path;
            },
            no_chdir => 1
        },$scan->{path});
        my $old = do {
            my @list = map { 
                $_->{path};
            } @{ $scan->{files} ||= [] };
            \@list;
        };

        my $diff = Array::Diff->diff($old,$new);
        if( $diff->count != 0 ){    
            say STDERR "something has changed to $scan->{path}, lets check what it is";
            push @scan_ids,$scan->{_id};
        }
    }

});

foreach my $scan_id(@scan_ids){
    my $scan = $scans->get($scan_id);

    #directory is ondertussen riebedebie
    if(!(-d $scan->{path})){
        say "$scan->{path} is gone, deleting from database";
        $scans->delete($scan->{_id});
        next;
    }

    say "checking $scan_id at $scan->{path}";
    $sth_get->execute( $scan->{user_id} ) or die($sth_get->errstr);
    my $user = $sth_get->fetchrow_hashref();
    if(!defined($user->{profile_id})){
        say STDERR "no profile defined for $user->{login}";
        next;
    }
    my $profile = $profiles->{ $user->{profile_id} };
    if(!$profile){
        say STDERR "strange, profile_id is defined in table users, but no profile could be found";
        next;
    }

    $scan->{check_log} = [];
    my @files = ();
    #acceptatie valt niet af te leiden uit het bestaan van foutboodschappen, want niet alle testen zijn 'fatal'
    my $accepted = 1;

    foreach my $test(@{ $profile->{packages} }){

        my $ref = get_package($test->{class},$test->{args});
        $ref->dir($scan->{path});        
        my($success,$errors) = $ref->test();

        push @{ $scan->{check_log} }, @$errors if !$success;
        unless(scalar(@files)){
            foreach my $stats(@{ $ref->file_info() }){
                push @files,file_info($stats->{path});
            }
        }
        if(!$success){
            if($ref->is_fatal || $test->{on_error} eq "stop"){
                $accepted = 0;
                last;
            }
        }
    }

    if(!$accepted){
        if($scan->{status} eq "incoming_back"){
            
            push @{$scan->{status_history}},{
                user_name =>"-",
                status => "incoming_error",
                datetime => Time::HiRes::time,
                comments => ""
            };          
            
        }else{
            $scan->{status_history}->[1] = {
                user_name =>"-",
                status => "incoming_error",
                datetime => Time::HiRes::time,
                comments => ""
            };
        }

        $scan->{status} = "incoming_error";
    }else{
        if($scan->{status} eq "incoming_back"){

            push @{$scan->{status_history}},{
                user_name =>"-",
                status => "incoming_ok",
                datetime => Time::HiRes::time,
                comments => ""
            };

        }else{
            $scan->{status_history}->[1] = {
                user_name =>"-",
                status => "incoming_ok",
                datetime => Time::HiRes::time,
                comments => ""
            };
            #verplaats maar pas 's nachts!
        }
        $scan->{status} = "incoming_ok";
    }
    $scan->{files} = \@files;
    $scans->add($scan);
}
