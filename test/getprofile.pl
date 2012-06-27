#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Profiles;

my $presolver = Imaging::Profiles->new(
    list => [
        ["BAG","Imaging::Profile::BAG"],
        ["TAR","Imaging::Profile::TAR"],
        ["NARA","Imaging::Profile::NARA"]
    ]
);
say $presolver->get_profile(shift);
