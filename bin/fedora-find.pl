#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:fedora);
use Data::Dumper;

my $query = shift;

my $result = fedora()->findObjects(query => $query);
die($result->error) unless $result->is_ok;
print $result->raw;
my $obj = $result->parse_content;
print Dumper($obj);
  
