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
  my $result = index_project->search(
    query => "*:*",
    start => $offset,
    limit => $limit            
  );
  $total = $result->total;
  for my $project(@{ $result->hits }){
    say $project->{_id};
    for(@{ $project->{list} }){
      say "\t$_";
    }
  }
  $offset += $limit;
}while($offset < $total);
