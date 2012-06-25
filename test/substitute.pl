#!/usr/bin/env perl
use Catmandu::Sane;

my $dir = "/mnt/data01/01_ready/geert/BHSL-PAP-000069/";
my $file = "/mnt/data01/01_ready/geert/BHSL-PAP-000069/BHSL-PAP-000069_2010_0002_MA.tif";
$file =~ s/^$dir//o;
say $file;
