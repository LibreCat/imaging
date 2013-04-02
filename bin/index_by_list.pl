#!/usr/bin/env perl
use Catmandu qw(:load);
use Dancer qw(:script);
use Catmandu::Sane;
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
