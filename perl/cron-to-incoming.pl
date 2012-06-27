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
use Imaging::Util qw(:files);
use Imaging::Dir::Info;

my $pidfile;
BEGIN {
    $pidfile = "/var/run/cron-imaging.pid";
    #lock
    if(-f $pidfile){
        local(*PID);
        open PID,$pidfile or die($!);
        local($/);
        $/ = undef;
        my $pid = <PID>;
        close PID;

        if(kill 0,$pid){
            die("Cannot run while other cronjob of imaging is still running\n");
        }
    }
    local(*PID);
    open PID,">$pidfile" or die($!);
    print PID $$;
    close PID;

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

END {
    unlink($pidfile);
}

use Dancer::Plugin::Imaging::Routes::Utils;

sub complain {
    say STDERR @_;
}

sub process_scan {
    my $scan = shift;
    my $oldpath = $scan->{path};    
    my $manifest = "$oldpath/__MANIFEST-MD5.txt";
    my $newpath = $scan->{newpath};
    say "$oldpath => $newpath";

    local(*FILE);

    #maak directory en plaats __FIXME.txt
    mkpath($newpath);
    #plaats __FIXME.txt
    open FILE,">$newpath/__FIXME.txt" or return complain($!);
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

        say "copying $oldpath/$filename to $newpath/$filename";
        #doe een copy operatie: indien een verplaatsing mislukt, kunnen we nog alles laten staan..
        if(
            !copy("$oldpath/$filename","$newpath/$filename")
        ){
            #mislukt: niets aan de hand. Alles staat nog in de map processed
            say STDERR "could not move $oldpath/$filename to $newpath/$filename";
            rmtree($newpath) if -d -w $newpath;
            return;
        }
    }
    close FILE; 
    
    #gelukt! verwijder nu oude map
    rmtree($oldpath);

    #TODO: rechten aanpassen aan dat van 01_ready submap

    #pas paden aan
    $scan->{path} = $newpath;
    my $dir_info = Imaging::Dir::Info->new(dir => $newpath);
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

    delete $scan->{$_} for(qw(busy));

    scans->add($scan);
    scan2index($scan);
    my($success,$error) = index_scan->commit;
    die(join('',@$error)) if !$success;
    status2index($scan,-1);
    ($success,$error) = index_log->commit;
    die(join('',@$error)) if !$success;
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
