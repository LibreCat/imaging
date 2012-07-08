#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Bag::Info;
use JSON;
use Data::Dumper;

my $baginfo = Imaging::Bag::Info->new();
for my $input(@ARGV){
    $baginfo->source($input);
    for($baginfo->keys){
        say "'$_' => ".join(',',$baginfo->values($_));
    }
}
