#!/usr/bin/env perl
use Catmandu;
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename qw();
use File::Copy qw(copy move);
use File::Path qw(mkpath);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use IO::CaptureOutput qw(capture_exec);
use Imaging::Util qw(:files);
use Imaging::Dir::Info;

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

#variabelen
sub mount_conf {
    config->{mounts}->{directories};
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

my $mount_conf = mount_conf();
my $scans = scans();

my @ids_to_be_renamed = ();
my $query = "status:\"rename_directory\"";
my($start,$limit,$total)=(0,1000,0);
do{

    my $result = $index_scan->search(
        query => $query,
        start => $start,
        limit => $limit
    );
    $total = $result->total;
    foreach my $hit(@{ $result->hits || [] }){
        push @ids_to_be_renamed,$hit->{_id};        
    }
    $start += $limit;

}while($start < $total);


foreach my $id(@ids_to_be_renamed){
    say $id;
    $scans->store->transaction(sub{
        my $scan = $scans->get($id);
        my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });

        #verwijder
        index_scan->delete($scan->{_id});
        index_log->delete_by_query(query => "scan_id:\"".$scan->{_id}."\"");
        $scans->delete($scan->{_id});

        say "\tremoved from database and index";

        my $old_path = $scan->{path};
        my $new_path = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login}."/".$scan->{new_id};

        #verplaats directory naar ready
        say "\tmoving from $scan->{path} to $new_path";        

        my $merror;
        if(!-d $new_path && !mkpath($new_path,{ error => \$merror })){
            say STDERR $merror;
            return;
        }
        if(!move($scan->{path},$new_path)){
            say $!;
            return;
        }
        $scan->{path} = $new_path;
        $scan->{_id} = $scan->{new_id};
        delete $scan->{new_id};

        say "\tdirectory moved from $old_path to $new_path";

        #update file info
        my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});
        my @files = ();
        foreach my $file(@{ $dir_info->files() }){
            push @files,file_info($file->{path});
        }
        $scan->{files} = \@files;
        $scan->{size} = $dir_info->size();

        #set status: incoming
        $scan->{status} = "incoming";
        push @{ $scan->{status_history} },{
            user_login => "-",
            status => "incoming",
            datetime => Time::HiRes::time,
            comments => ""
        };

        #datum aanpassen
        $scan->{datetime_last_modified} = Time::HiRes::time;
        $scan->{datetime_directory_last_modified} = mtime_latest_file($scan->{path});


        #sla terug op
        delete $scan->{$_} foreach(qw(busy busy_reason new_id));
        $scans->add($scan);        
        scan2index($scan);
        status2index($scan);

        say "$scan->{_id} stored to database";

        #commit
        my($success,$error) = index_scan->commit;
        die(join('',@$error)) if !$success;
        ($success,$error) = index_log->commit;
        die(join('',@$error)) if !$success;

        say "changes committed";

    });
}

say "$this_file ended at ".local_time;
