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
        dirname(dirname(
            Cwd::realpath( __FILE__)
        ))
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
sub upload_idle_time {
    state $upload_idle_time = do {
        my $config = config;
        my $time = data_at($config,"mounts.directories.ready.upload_idle_time");
        my $return;
        if($time){
            my %opts = ();
            my @keys = qw(seconds minutes hours days);
            foreach(@keys){
                $opts{$_} = is_string($time->{$_}) ? int($time->{$_}) : 0;
            }
            $return = convertInterval(%opts,ConvertTo => "seconds");
        }else{
            $return = 60;
        }
        $return;
    };
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
# 1. lijst mappen
# 2. Map staat niet in databank: voeg nieuw record toe
# 3. Map staat wel in databank:
#     3.1. Map die terugkeert uit 03_reprocessing? Zet 1ste keer status op 'incoming' en zet datetime_last_modified op mtime van de map. Pas tevens de bestandslijst aan. Vergelijk de eerstvolgende
#          keer datetime_last_modified en mtime, en indien gelijk, zet status op 'incoming_done'
#     3.2. Map die lange upload nodig heeft? Vergelijk datetime_last_modified met mtime van de map. Indien gelijk, dan wordt upload als afgelopen beschouwd en zet status op 'incoming_done'


my @users =  dbi_handle->quick_select("users",{ has_dir => 1});
my @scan_ids_ready = ();

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
            my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($dir);

            #wacht totdat er lange tijd niets met de map is gebeurt!!
            my $seconds_since_modified = time - $mtime;
            if($seconds_since_modified <= upload_idle_time()){
                say "directory $basename probably busy (last modified $seconds_since_modified seconds ago)";
                next;
            }
            #map komt nog niet voor in de databanken
            elsif(!$scan){
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
                    #mtime van de diretory
                    datetime_directory_last_modified => $mtime,
                    #wanneer heeft het systeem de status van dit record voor het laatst aangepast
                    datetime_last_modified => Time::HiRes::time,
                    #wanneer heeft het systeem de directory voor het eerst zien staan
                    datetime_started => Time::HiRes::time,
                    project_id => undef,
                    metadata => [],
                    comments => [],
                    warnings => []
                };
                $scans->add($scan);
            }
            #map komt terug uit 03_reprocessing. Opgelet: een andere gebruiker kan ook gewoon dezelfde map hebben verwerkt!
            elsif("$scan->{user_id}" eq "$user->{id}" && $scan->{status} eq "reprocess_scans"){
                
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

                my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($dir);
                $scan->{datetime_directory_last_modified} = $mtime;

                $scans->add($scan);

            }
            #update index_scan en index_log
            scan2index($scan);
            status2index($scan);

            push @scan_ids_ready,$scan->{_id};
        }
        close CMD;   
    }catch{
        chomp($_);
        say STDERR $_;
    };
}
#stap 2: zijn er scandirectories die hier al te lang staan?
my @delete = ();
my @warn = ();
foreach my $scan_id(@scan_ids_ready){
    my $scan = $scans->get($scan_id);
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
};
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

#stap 3: doe check -> filter lijst van scan_ids_ready op mappen die gecontroleerd moeten worden:
# 1. mappen die nog geen controle zijn gepasseerd, worden gecontroleerd
# 2. mappen die wel eens gecontroleerd zijn, maar ongewijzigd sindsdien, worden niet gecontroleerd
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= require_package($class)->new(%$args);
}
my @scan_ids_test = ();
foreach my $scan_id(@scan_ids_ready){

    my $scan = $scans->get($scan_id);
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($scan->{path});

    #check nieuwe directories
    if(
        $scan->{status} eq "incoming" || 
        $scan->{status} eq "incoming_back"
    ){
        push @scan_ids_test,$scan->{_id};
    }
    #check slechte en goede indien iets gewijzigd
    elsif(
        $scan->{status} eq "incoming_error" ||
        $scan->{status} eq "incoming_ok"
    ){
        push @scan_ids_test,$scan->{_id} if $mtime > $scan->{datetime_directory_last_modified};
    }

};

foreach my $scan_id(@scan_ids_test){
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

    my $index_last_error = List::MoreUtils::last_index {
        $_->{status} eq "incoming_error";
    } @{$scan->{status_history}};

    $scan->{status} = $num_fatal > 0 ? "incoming_error":"incoming_ok";
    
    my $status_history_object = {
        user_name =>"-",
        status => $scan->{status},
        datetime => Time::HiRes::time,
        comments => ""
    };

    if($index_last_error >= 0){

        $scan->{status_history}->[$index_last_error] = $status_history_object;
    
    }else{

        push @{ $scan->{status_history} },$status_history_object;

    }

    $scan->{files} = \@files;

    $scan->{datetime_last_modified} = Time::HiRes::time;

    #update index_scan en index_log
    scan2index($scan);
    status2index($scan);

    $scans->add($scan);
}
if(scalar(@scan_ids_ready) > 0){
    index_log->store->solr->optimize();
    index_scan->store->solr->optimize()
}
