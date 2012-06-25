#!/usr/bin/env perl
use Catmandu::Sane;
use Imaging::Dir::Info;

my $info = Imaging::Dir::Info->new(dir => shift);
#say $_->{path} for(@{ $info->files });
say "size:".$info->size();
