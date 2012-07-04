#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Test::Dir::checkDirStructure;
use Imaging::Dir::Info;

my $info = Imaging::Dir::Info->new(dir => shift);
say "files:".scalar(@{ $info->files });
say "$_->{path}" for(@{ $info->files });
say "directories:".scalar(@{ $info->directories });
say "$_->{path}" for(@{ $info->directories });

my $check = Imaging::Test::Dir::checkDirStructure->new(dir_info => $info);
my($success,$errors) = $check->test();
if(!$success){
    say $_ for(@$errors);
}else{
    say "OK";
}
