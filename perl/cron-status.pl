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
use URI::Escape qw(uri_escape);
use LWP::UserAgent;

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
sub construct_query {
    my $data = shift;
    my @parts = ();
    for my $key(keys %$data){
        if(is_array_ref($data->{$key})){
            for my $val(@{ $data->{$key} }){
                push @parts,uri_escape($key)."=".uri_escape($val);
            }
        }else{
            push @parts,uri_escape($key)."=".uri_escape($data->{$key});
        }
    }
    join("&",@parts);
}
sub move_scan {
    my $scan = shift;
    my $new_path = $scan->{new_path};


    #is de operatie gezond?
    if(!(
        is_string($scan->{path}) && -d $scan->{path}
    )){
        my $p = $scan->{path} || "";
        say STDERR "Cannot move from 02_processed: scan directory '$p' does not exist";
        return;

    }elsif(!is_string($new_path)){

        say STDERR "Cannot move from $scan->{path} to '': new_path is empty";
        return;

    }elsif(! -d dirname($new_path) ){

        say STDERR "Will not move from $scan->{path} to $new_path: parent directory of $new_path does not exist";
        return;

    }elsif(-d $new_path){

        say STDERR "Will not move from $scan->{path} to $new_path: directory already exists";
        return;

    }elsif(!( 
        -w dirname($scan->{path}) &&
        -w $scan->{path})
    ){

        say STDERR "Cannot move from $scan->{path} to $new_path: system has no write permissions to $scan->{path} or its parent directory";
        return;

    }elsif(! -w dirname($new_path) ){
        
        say STDERR "Cannot move from $scan->{path} to $new_path: system has no write permissions to parent directory of $new_path";
        return;

    }


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

    update_scan($scan);
    update_status($scan,-1);

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

#status update 1: files die verplaatst moeten worden op vraag van dashboard
{
    my $query = "status:\"reprocess_scans\" OR status:\"reprocess_scans_qa_manager\"";
    my($start,$limit,$total)=(0,1000,0);
    my @ids = ();
    do{

        my $result = $index_scan->search(
            query => $query,
            start => $start,
            limit => $limit
        );
        $total = $result->total;
        foreach my $hit(@{ $result->hits || [] }){
            push @ids,$hit->{_id};
        }
        $start += $limit;

    }while($start < $total);
    for my $id(@ids){
        move_scan(scans->get($id));
    }
}
#status update 2: zitten objecten in archivering reeds in archief?
{

    my $query = "status:\"archiving\"";
    my($start,$limit,$total)=(0,1000,0);
    my @ids = ();
    do{

        my $result = $index_scan->search(
            query => $query,
            start => $start,
            limit => $limit
        );
        $total = $result->total;
        foreach my $hit(@{ $result->hits || [] }){
            push @ids,$hit->{_id};
        }
        $start += $limit;

    }while($start < $total);

    my $ua = LWP::UserAgent->new( cookie_jar => {}, ssl_opts => { verify_hostname => 0 } );
    my $base_url = config->{archive_site}->{base_url}.config->{archive_site}->{rest_api}->{path};

    for my $id(@ids){
        my $scan = scans->get($id);
        my $url = "$base_url?".construct_query({ func => "count",q => $id });
        say "fetching $url";
        my $res = $ua->get($url);        
        if($res->is_error){            
            say STDERR $res->content;
            next;
        }
        say "fetch succcessfull";
        say $res->content;
        try{
            my $json = from_json($res->content);
            #opgelet: wat als je iets moet overschrijven? Want je gebruikt daarbij een id
            #die reeds in het archief zit!
            if($json->{found} == 1){
                $scan->{status} = "archived";
                push @{ $scan->{status_history} },{
                    user_login =>"-",
                    status => "archived",
                    datetime => Time::HiRes::time,
                    comments => ""
                };
                $scan->{datetime_last_modified} = Time::HiRes::time;
                update_scan($scan);
                update_status($scan,-1);
            }
        }catch{
            say STDERR $_;
        };
    }
}

#check toestand jobs in mediamosa voor status:process en profile_id:NARA

#status update 3: wat is reeds succesvol gearchiveerd EN aanvaard als dusdanig?
{

    my $query = "status:\"archived_ok\"";
    my($start,$limit,$total)=(0,1000,0);
    my @ids = ();
    do{

        my $result = $index_scan->search(
            query => $query,
            start => $start,
            limit => $limit
        );
        $total = $result->total;
        foreach my $hit(@{ $result->hits || [] }){
            push @ids,$hit->{_id};
        }
        $start += $limit;

    }while($start < $total);

    for my $id(@ids){
        my $scan = scans->get($id);
        next if !$scan;
        say "$id is 'archived_ok': removing ".$scan->{path}." and setting status to 'done'";
        $scan->{status} = "done";
        push @{ $scan->{status_history} },{
            user_login =>"-",
            status => "done",
            datetime => Time::HiRes::time,
            comments => ""
        };
        $scan->{datetime_last_modified} = Time::HiRes::time;
        #update_scan($scan);
        #update_status($scan,-1);
        #rmtree($scan->{path});
    }
}

say "$this_file ended at ".local_time;
