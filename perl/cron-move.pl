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

BEGIN {
    my $appdir = Cwd::realpath("..");
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
my $scans = scans();

my @ids_to_be_moved = ();

$scans->each(sub{
    my $scan = shift;
    if(
        $scan->{status} eq "reprocess_scans" && 
        $scan->{busy} && $scan->{busy_reason} eq "move"
        && is_string($scan->{newpath})
    ){
        push @ids_to_be_moved,$scan->{_id};
    }
});
foreach my $id(@ids_to_be_moved){
    say $id;
    my $scan = $scans->get($id);
    
    my $newpath = $scan->{newpath};
    my $oldpath = $scan->{path};

    mkpath($newpath);
    if(move($oldpath,$newpath)){
        say "\tmoved from $oldpath to $newpath";
        $scan->{path} = $newpath;
        foreach my $file(@{ $scan->{files} }){
            $file->{path} =~ s/^$oldpath/$newpath/;
        }

        #update file info
        foreach my $file(@{ $scan->{files} }){
            my $new_stats = file_info($file->{path});
            $file->{$_} = $new_stats->{$_} foreach(keys %$new_stats);
        }

        my @deletes = qw(busy busy_reason newpath);
        delete $scan->{$_} foreach(@deletes);

        $scans->add($scan); 
    }else{
        say STDERR "unable to move $oldpath to $newpath:$!";
    }
}
