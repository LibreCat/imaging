#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use Imaging::Bag::Info;
use Imaging::Profile::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);
use File::Basename qw();
use Cwd qw(abs_path);
use IO::CaptureOutput qw(capture_exec);
use Data::UUID;

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

say "indexing";
my @ids = ();
{
    my($offset,$limit,$total) = (0,1000,0);
    do{
        my $result = index_scan->search(
            query => "*",
            start => $offset,
            limit => $limit            
        );
        $total = $result->total;
	for my $scan(@{ $result->hits }){
		push @ids,$scan->{_id};
	}
	$offset += $limit;
    }while($offset < $total);
}

foreach my $id(@ids){
	my $scan = scans->get($id);
	say $id;
    	update_scan($scan);
}
