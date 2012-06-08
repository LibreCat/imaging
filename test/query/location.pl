#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Dir::Query::Location;

my $path = shift;
my $translator = Imaging::Dir::Query::Location->new;
if($translator->check($path)){
    my @queries = $translator->queries($path);
    say $_ foreach(@queries);
}else{
    exit 1;
}
