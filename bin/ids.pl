#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(index_scan);

my $query = shift;
index_scan->searcher(

  query => $query,
  limit => 1000

)->each(sub{

  say $_[0]->{_id};

});
