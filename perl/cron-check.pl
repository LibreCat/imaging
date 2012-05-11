#!/usr/bin/env perl
use Dancer qw(:script);
use Catmandu qw(store);

use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(require_package :is);
use List::MoreUtils;
use File::Basename qw();
use File::Path;
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
use File::MimeInfo;
our($a,$b);

BEGIN {
    my $appdir = Cwd::realpath("..");
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}
sub _test_deep_hash {
    my($hash,@keys) = @_;
    my $key = pop @keys;
    if(!exists($hash->{$key})){
        return 0;
    }else{
        return _test_deep_hash(
            $hash->{$key},@keys
        );
    }
}
sub test_deep_hash {
    my($hash,$test) = @_;
    _test_deep_hash($hash,split('.',$test));
}
sub seconds_day { 3600*24; }
sub diff_days {
    my($date1,$date2)=@_;
    my $diff = ($date2 - $date1) / seconds_day();
    if($diff > 0){
        $diff = POSIX::floor($diff);
    }else{
        $diff = POSIX::ceil($diff);
    }
    return $diff;
}
sub core_opts {
    state $core_opts = do {
        my $catmandu_config = Catmandu->config;
        {
            data_source => $catmandu_config->{store}->{core}->{options}->{data_source},
            username => $catmandu_config->{store}->{core}->{options}->{username},
            password => $catmandu_config->{store}->{core}->{options}->{password}
        };
    };
}
sub core {
    state $core = store("core");
}
sub users {
    state $users = do {
        my $core_opts = core_opts();
        my $users = DBI->connect($core_opts->{data_source}, $core_opts->{username}, $core_opts->{password},{
            AutoCommit => 1,
            RaiseError => 1,
            mysql_auto_reconnect => 1
        });
    };
}
sub users_each {
    state $x = users->prepare("select * from users where has_dir = 1");
}
sub users_get {
    state $x = users->prepare("select * from users where id = ?");
}
sub scans {
    state $scans = core->bag("scans");
}
sub profiles {
    config->{profiles} ||= {};
}
sub mount_conf {
    config->{mounts}->{directories};
}
#how long before a warning is created?
#-1 means never
sub warn_after {
    state $warn_after = do {
        my $config = config;
        if( 
            defined($config->{mounts}) && defined($config->{mounts}->{subdirectories}) && 
            defined($config->{mounts}->{subdirectories}->{ready}) &&
            is_hash_ref($config->{mounts}->{subdirectories}->{ready}->{warn_after})
        ){
            my $warn_after = $config->{mounts}->{subdirectories}->{ready}->{warn_after};
            return convertInterval(
                seconds => $warn_after->{seconds},
                minutes => $warn_after->{minutes},
                hours => $warn_after->{hours},
                days => $warn_after->{days},
                ConvertTo => "seconds"
            );
        }else{
            return -1;
        }
    };
}
sub do_warn {
    my $scan = shift;
    my $warn_after = warn_after();
    print "$warn_after\n";
    if($warn_after < 0){
        return 1;
    }else{
        return ( time + $warn_after - $scan->{datetime_started} ) < 0;
    }
}
#how long before the scan is deleted?
#-1 means never
sub delete_after {
    state $delete_after = do {
        my $config = config;
        if(
            defined($config->{mounts}) && defined($config->{mounts}->{ready}) && defined($config->{mounts}->{subdirectories}) &&
            is_hash_ref($config->{mounts}->{subdirectories}->{ready}->{delete_after})
        ){
            my $delete_after = $config->{mounts}->{subdirectories}->{ready}->{delete_after};
            return convertInterval(
                seconds => $delete_after->{seconds},
                minutes => $delete_after->{minutes},
                hours => $delete_after->{hours},
                days => $delete_after->{days},
                ConvertTo => "seconds"
            );
        }else{
            return -1;
        }
    };
}
sub do_delete {
    my $scan = shift;
    my $delete_after = delete_after();
    my $warn_after = warn_after();
    if($delete_after < 0){
        return 0;
    }else{
        return ( ( time + $warn_after + $delete_after ) - $scan->{datetime_started} ) < 0;
    }
}
sub delete_scan_data {
    my $scan = shift;
    try{
        rmtree($scan->{path});
    }catch{
        say STDERR $_;
    };
}
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
            name => File::Basename::basename($path),
            path => $path,
            atime => $atime,
            mtime => $mtime,
            ctime => $ctime,
            size => $size,
            content_type => mimetype($path),
            mode => $mode
        };
    }else{
        return {
            name => File::Basename::basename($path),
            path => $path,
            error => $!
        }
    }
}

my $sth_each = users_each;
my $sth_get = users_get;
my $mount_conf = mount_conf;
my $scans = scans;

#stap 1: zoek scans
$sth_each->execute() or die($sth_each->errstr());
while(my $user = $sth_each->fetchrow_hashref()){
    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};
    if(! -d $ready ){
        say STDERR "directory $ready of user $user->{login} does not exist";
        next;
    }
    try{
        open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d | sort |" or die($!);
        while(my $dir = <CMD>){
            chomp($dir);    
            my $basename = File::Basename::basename($dir);
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
                    datetime_started => Time::HiRes::time,
                    project_id => undef,
                    metadata => [],
                    comments => [],
                    warnings => []
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
    }catch{
        say STDERR "could not read directory $ready of user $user->{login}: $_";
    };
}
#stap 2: zijn er scandirectories die hier al te lang staan?
my @delete = ();
my @warn = ();
$scans->each(sub{
    my $scan = shift;
    if(do_delete($scan)){
        push @delete,$scan->{_id};
    }elsif(do_warn($scan)){
        push @warn,$scan->{_id};
    }
});
foreach my $id(@delete){
    my $scan = $scans->get($id);
    delete_scan_data($scan);
    $scans->delete($id);
}
foreach my $id(@warn){
    my $scan = $scans->get($id);
    $scan->{warnings} = [{
        datetime => Time::HiRes::time,
        text => "Deze map heeft de tijdslimiet op validatie niet gehaald, en zal binnenkort verwijderd worden",
        username => "-"
    }];   
    $scan->add($scan);
}

#stap 3: doe check
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= require_package($class)->new(%$args);
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
    my $profile = profiles->{ $user->{profile_id} };
    if(!$profile){
        say STDERR "strange, profile_id is defined in table users, but no profile could be found";
        next;
    }

    $scan->{check_log} = [];
    my @files = ();
    #acceptatie valt niet af te leiden uit het bestaan van foutboodschappen, want niet alle testen zijn 'fatal'
    my $num_fatal = 0;

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
            if($test->{on_error} eq "stop"){
                $num_fatal = 1;
                last;
            }elsif($ref->is_fatal){
                $num_fatal++;
            }
        }
    }

    if($num_fatal > 0){
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
