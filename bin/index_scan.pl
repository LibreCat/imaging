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


my($offset,$limit,$total) = (0,1000,0);
do{
  my $result = index_scan->search(
    query => $query,
    start => $offset,
    limit => $limit            
  );
  $total = $result->total;
  for my $scan(@{ $result->hits }){
    print $scan->{_id};
    for(@attr){
      print " ".($scan->{$_} // "<not defined>");
    }
    print "\n";
  }
  $offset += $limit;
}while($offset < $total);
