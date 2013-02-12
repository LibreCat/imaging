#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Catmandu::Sane;
use File::Basename qw();
use Cwd qw(abs_path);

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

my $query = shift;
{
    my($offset,$limit,$total) = (0,1000,0);
    do{
        my $result = index_scan->search(
            query => $query,
            start => $offset,
            limit => $limit            
        );
        $total = $result->total;
	for my $scan(@{ $result->hits }){
		say $scan->{_id};
	}
	$offset += $limit;
    }while($offset < $total);
}
