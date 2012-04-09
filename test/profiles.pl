#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;

my $store = Catmandu::Store::DBI->new(
	data_source => "dbi:mysql:database=imaging",
	username => "imaging",
	password => "imaging"
);
my $profiles = $store->bag("profiles");

my $profile = $profiles->add({
    _id => "NARA",
    packages => [
        {
            class => "Imaging::Test::Dir::scan",
            args => {},
            on_error => "stop"
        },
        {
            class => "Imaging::Test::Dir::checkPermissions",
            args => {},
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::hasNoFiles",
            args => {
                patterns => ['^\./']
            },
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::checkEmpty",
            args => {},
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::checkTIFF",
            args => {
                valid_patterns => ['\.tif(?:f)?$']
            },
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::checkPDF",
            args => {
                valid_patterns => ['\.pdf$']
            },
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::checkJPEG",
            args => {
                valid_patterns => ['\.jp(?:e)g$']
            },
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::checkFilename",
            args => {},
            on_error => "continue"
        }
    ]
});
