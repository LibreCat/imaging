#!/usr/bin/env perl
use Catmandu::Sane;
use all qw(Imaging::Dir::Query::*);

my $path = shift;
my @list = qw(Imaging::Dir::Query::BAG Imaging::Dir::Query::RUG01 Imaging::Dir::Query::Location);
my @queries = ();
foreach my $package_name(@list){
    say STDERR "checking $package_name";
    my $translator = $package_name->new;
    if($translator->check($path)){
        @queries = $translator->queries($path);
        last;
    }
}
exit 1 unless scalar(@queries);
say $_ foreach(@queries);
