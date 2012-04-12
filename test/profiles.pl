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
			class => "Imaging::Test::Dir::checkMD5",
			args => {
				is_optional => 1
			},
			on_error => "continue"
		},
        {
            class => "Imaging::Test::Dir::checkTIFF",
            args => {
				valid_patterns => [
					'^(?!manifest\.txt$)'
				]
			},
            on_error => "continue"
        },
        {
            class => "Imaging::Test::Dir::NARA::checkFilename",
            args => {
				valid_patterns => [
                    '^(?!manifest\.txt$)'
                ]
			},
            on_error => "continue"
        }
    ]
});
