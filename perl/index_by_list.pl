#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Catmandu::Sane;

BEGIN {
   
    #load configuration
    my $appdir = "/opt/Imaging";
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}

use Dancer::Plugin::Imaging::Routes::Utils;

my $file = shift || "";
(-r -f $file) or die("$file does not exist!\n");

open STDIN,$file or die($!);

my $attr = shift || die("attribute not given!\n");

my $id;
while($id = <STDIN>){
	chomp $id;
	my $scan = scans->get($id);
	next if !$scan;
	say $scan->{$attr};
}
