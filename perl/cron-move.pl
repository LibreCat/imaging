#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use File::Copy qw(copy move);
use File::Path qw(mkpath);
use Cwd qw(abs_path);
use File::Spec;
use YAML;
use Try::Tiny;
use DBI;

#variabelen
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
sub config {
    state $config = do {
        my $config_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
        YAML::LoadFile($config_file);
    };
}
sub store_opts {
    state $opts = do {
        my $config = config;
        my %opts = (
            data_source => $config->{store}->{core}->{options}->{data_source},
            username => $config->{store}->{core}->{options}->{username},
            password => $config->{store}->{core}->{options}->{password}
        );
        \%opts;
    };
}
sub store {
    state $store = Catmandu::Store::DBI->new(%{ store_opts() });
}
sub scans {
    state $scans = store()->bag("scans");
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
