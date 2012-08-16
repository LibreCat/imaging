#!/usr/bin/env perl
use Catmandu::Sane;

my $file = shift;

$/ = undef;
open FILE,$file or die($!);
my $content = <FILE>;
close FILE;

if($content =~ /new asset id: (\w+)\n/m){
    say "asset id:$1";
}
