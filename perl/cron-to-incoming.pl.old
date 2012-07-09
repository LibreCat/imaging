#!/usr/bin/env perl
use Catmandu;
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename qw();
use File::Copy qw(copy move);
use File::Path qw(mkpath rmtree);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use IO::CaptureOutput qw(capture_exec);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use File::Pid;

BEGIN {
    #load configuration
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

sub complain {
    say STDERR @_;
}

sub process_scan {
    my $scan = shift;

    #gebruiker bestaat?
    my $login;
    if($scan->{new_user}){
        $login = $scan->{new_user};
    }else{
        my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
        $login = $user->{login};
    }

    my($user_name,$pass,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire)=getpwnam($login);
    if(!is_string($uid)){
        say STDERR "$login is not a valid system user!";
        return;
    }elsif($uid == 0){
        say STDERR "root is not allowed as user";
        return;
    }
    my $group_name = getgrgid($gid);


    my $old_path = $scan->{path};    
    my $manifest = "$old_path/__MANIFEST-MD5.txt";
    my $new_path = $scan->{new_path};
    say "$old_path => $new_path";

    local(*FILE);

    #maak directory en plaats __FIXME.txt
    mkpath($new_path);
    #plaats __FIXME.txt
    open FILE,">$new_path/__FIXME.txt" or return complain($!);
    print FILE $scan->{status_history}->[-1]->{comments};
    close FILE;

 
    #verplaats bestanden die opgelijst staan in __MANIFEST-MD5.txt naar 01_ready
    #andere bestanden laat je staan (en worden dus verwijderd)
    open FILE,$manifest or return complain($!);
    while(my $line = <FILE>){
        $line =~ s/\r\n$/\n/;
        chomp($line);
        utf8::decode($line);
        my($checksum,$filename)=split(/\s+/o,$line);

        mkpath(File::Basename::dirname("$new_path/$filename"));   
        say "moving $old_path/$filename to $new_path/$filename";
        if(
            !move("$old_path/$filename","$new_path/$filename")
        ){
            say STDERR "could not move $old_path/$filename to $new_path/$filename";
            return;
        }
    }
    close FILE; 
    
    #gelukt! verwijder nu oude map
    rmtree($old_path);

    
    #pas paden aan
    $scan->{path} = $new_path;
    my $dir_info = Imaging::Dir::Info->new(dir => $new_path);
    my @files = ();
    foreach my $file(@{ $dir_info->files }){
        push @files,file_info($file->{path});
    }
    $scan->{files} = \@files;

    #update databank en index
    $scan->{status} = "incoming";
    push @{ $scan->{status_history} },{
        user_login =>"-",
        status => "incoming",
        datetime => Time::HiRes::time,
        comments => ""
    };
    $scan->{datetime_last_modified} = Time::HiRes::time;

    #gedaan ermee
    delete $scan->{$_} for(qw(busy new_path new_user));

    scans->add($scan);
    scan2index($scan);
    my($success,$error) = index_scan->commit;
    die(join('',@$error)) if !$success;
    status2index($scan,-1);
    ($success,$error) = index_log->commit;
    die(join('',@$error)) if !$success;

    #done? rechten aanpassen aan dat van 01_ready submap
    try{
        `chown -R $user_name:$group_name $scan->{path} && chmod -R 755 $scan->{path}`;
    }catch{
        say STDERR $_;
    };
}


#voer niet uit wanneer imaging-register.pl draait!

my $pidfile = data_at(config,"cron.register.pidfile") ||  "/var/run/imaging-register.pid";
my $pid = File::Pid->new({
    file => $pidfile
});
if(-f $pid->file && $pid->running){
    die("Cannot run while registration is running\n");
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

my $scans = scans();
my $index_scan = index_scan();

my $query = "status:\"reprocess_scans\" OR status:\"reprocess_scans_qa_manager\"";
my($start,$limit,$total)=(0,1000,0);
do{

    my $result = $index_scan->search(
        query => $query,
        start => $start,
        limit => $limit,
        reify => $scans
    );
    $total = $result->total;
    foreach my $hit(@{ $result->hits || [] }){
        process_scan($hit);
    }
    $start += $limit;

}while($start < $total);

say "$this_file ended at ".local_time;
