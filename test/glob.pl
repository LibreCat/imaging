#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Dir::Info;
use Imaging::Test::Dir::checkDirStructure;

my $dir = shift;
my $dir_info = Imaging::Dir::Info->new(dir => $dir);
my $check = Imaging::Test::Dir::checkDirStructure->new(
    dir_info => $dir_info,
    conf => {
        'glob' => "*.tif manifest-md5.txt",
        "all" => 1,
        "message" => "directory must have only *.tif or manifest-md5.txt"
    }
);
my($success,$errors)=$check->test();
say "$_" for(@$errors);
