#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use Catmandu::FedoraCommons;
use Data::Dumper;
use DateTime::Format::Strptime;

my $query = shift;

my $url = "http://localhost:4000/fedora";
my $fedora = Catmandu::FedoraCommons->new($url,"","");

my $result = $fedora->findObjects(query => $query);
die($result->error) unless $result->is_ok;
print $result->raw;
my $obj = $result->parse_content;
print Dumper($obj);
  
