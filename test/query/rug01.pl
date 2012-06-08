#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Dir::Query::RUG01;

my $path = shift;
my $translator = Imaging::Dir::Query::RUG01->new;
if($translator->check($path)){
    my @queries = $translator->queries($path);
    say $_ foreach(@queries);
}else{
    exit 1;
}
