#!/usr/bin/env perl
use Dancer qw(:script);
use Catmandu qw(store);
use Imaging::Util qw(data_at);

use Catmandu::Sane;
use Catmandu::Util qw(require_package :is);
use List::MoreUtils;
use File::Basename qw();
use File::Path;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use Array::Diff;
use File::Find;
use File::MimeInfo;
use Time::Interval;
our($a,$b);

BEGIN {
    my $appdir = Cwd::realpath(
        dirname(dirname(__FILE__))
    );
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}
use Dancer::Plugin::Imaging::Routes::Utils;

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
        my $warn_after = data_at($config,"mounts.directories.ready.warn_after");
        my $return;
        if($warn_after){
            my %opts = ();
            my @keys = qw(seconds minutes hours days);
            foreach(@keys){
                $opts{$_} = is_string($warn_after->{$_}) ? int($warn_after->{$_}) : 0;
            }
            $return = convertInterval(%opts,ConvertTo => "seconds");
        }else{
            $return = -1;
        }
        $return;
    };
}
sub do_warn {
    my $scan = shift;
    my $warn_after = warn_after();
    if($warn_after < 0){
        return 1;
    }else{
        return ( $scan->{datetime_started} + $warn_after - time ) < 0;
    }
}
#how long before the scan is deleted?
#-1 means never
sub delete_after {
    state $delete_after = do {
        my $config = config;
        my $delete_after = data_at($config,"mounts.directories.ready.delete_after");
        my $return;
        if($delete_after){
            my %opts = ();
            my @keys = qw(seconds minutes hours days);
            foreach(@keys){
                $opts{$_} = is_string($delete_after->{$_}) ? int($delete_after->{$_}) : 0;
            }
            $return = convertInterval(%opts,ConvertTo => "seconds");
        }else{
            $return = -1;
        }
        $return;
    };
}
sub do_delete {
    my $scan = shift;
    my $delete_after = delete_after();
    my $warn_after = warn_after();  
    if($delete_after < 0){
        return 0;
    }else{
        return ( ( $scan->{datetime_started} + $warn_after + $delete_after ) - time ) < 0;
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

my $mount_conf = mount_conf;
my $scans = scans;

#stap 1: zoek scans
my @users =  dbi_handle->quick_select("users",{ has_dir => 1});

foreach my $user(@users){

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
                $scan = {
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
                };
                $scans->add($scan);
            }else{
                #het kan natuurlijk ook zijn dat een andere gebruiker dezelfde map heeft verwerkt..
                if("$scan->{user_id}" eq "$user->{id}" && $scan->{status} eq "reprocess_scans"){
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
                    #datum aanpassen
                    $scan->{datetime_last_modified} = Time::HiRes::time;

                    $scans->add($scan);
                }
            }
            #update index_scan en index_log
            scan2index($scan);
            status2index($scan);
        }
        close CMD;   
    }catch{
        chomp($_);
        say STDERR "could not read directory $ready of user $user->{login}: $_";
    };
}
#stap 2: zijn er scandirectories die hier al te lang staan?
my @delete = ();
my @warn = ();
$scans->each(sub{
    my $scan = shift;
    if(do_delete($scan)){
        say "ah too late man!";
        #voor later
        return;
        say "nothing too see here!";

        push @delete,$scan->{_id};
    }elsif(do_warn($scan)){
        say "ah a warning!";
        push @warn,$scan->{_id};
    }
});
foreach my $id(@delete){
    my $scan = $scans->get($id);
    say "ah no! You're deleting things!";
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
    $scans->add($scan);
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
    my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
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

    $scan->{datetime_last_modified} = Time::HiRes::time;

    #update index_scan en index_log
    scan2index($scan);
    status2index($scan);

    $scans->add($scan);
}

index_log->store->solr->optimize();
index_scan->store->solr->optimize()
