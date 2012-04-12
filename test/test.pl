#!/usr/bin/env perl
use Catmandu::Sane;

my $input = shift || "";;
say "'$input'";
if ($input =~ /^(?!manifest\.txt$)/){
	say "yes";
}else{
	say "no";
}
