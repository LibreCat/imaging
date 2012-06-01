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
use File::MimeInfo;
use IO::CaptureOutput qw(capture_exec);
use Data::Dumper;

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
sub mount_conf {
    config->{mounts}->{directories};
}


my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

my $scans = scans();

my @ids_to_be_renamed = ();

$scans->each(sub{
    my $scan = shift;
    if(
        $scan->{status} eq "rename_directory" && is_string($scan->{new_id})
    ){
        push @ids_to_be_renamed,$scan->{_id};
    }
});

my $mount_conf = mount_conf();
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

        #set status: renaming_directory
        push @{ $scan->{status_history} },{
            user_login => "-",
            status => "renaming_directory",
            datetime => Time::HiRes::time,
            comments => ""
        };

        my $old_path = $scan->{path};
        my $new_path = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login}."/".File::Basename::basename($scan->{new_id});

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
        foreach my $file(@{ $scan->{files} }){
            print "\t".$file->{path}." => ";
            $file->{path} =~ s/^$old_path/$new_path/;
            print $file->{path}."\n";
        }
        foreach my $file(@{ $scan->{files} }){
            my $new_stats = file_info($file->{path});
            $file->{$_} = $new_stats->{$_} foreach(keys %$new_stats);
        }
        

        #set status: incoming_back
        $scan->{status} = "incoming_renamed";
        push @{ $scan->{status_history} },{
            user_login => "-",
            status => "incoming_renamed",
            datetime => Time::HiRes::time,
            comments => ""
        };

        #datum aanpassen
        $scan->{datetime_last_modified} = Time::HiRes::time;
        my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($scan->{path});
        $scan->{datetime_directory_last_modified} = $mtime;


        #sla terug op
        delete $scan->{$_} foreach(qw(busy busy_reason new_id));
        $scans->add($scan);        
        scan2index($scan);
        status2index($scan);

        say "$scan->{_id} stored to database";

        #commit
        my($success,$error) = index_scan->commit;
        die($error) if !$success;
        ($success,$error) = index_log->commit;
        die($error) if !$success;

        say "changes committed";

    });
}

say "$this_file ended at ".local_time;
