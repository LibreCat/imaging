#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:all);
use Getopt::Long;


my($query,@attr) = ("*:*");

GetOptions(
  "query=s" => \$query,
  "attr=s" => \@attr
);


index_scan->searcher(
  query => $query,
  limit => 1000
)->each(sub{
  my $scan = shift;
  print $scan->{_id};
  for(@attr){
    print " ".($scan->{$_} // "<not defined>");
  }
  print "\n";
});
