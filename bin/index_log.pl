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

index_log->searcher(
  query => $query,
  limit => 1000
)->each(sub{
  my $r = shift;
  print $r->{_id};
  for(@attr){
    print " ".($r->{$_} // "<not defined>");
  }
  print "\n";
});
