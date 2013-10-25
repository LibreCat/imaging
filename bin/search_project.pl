#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:store);
use Getopt::Long;

my($query,@attr) = ("*:*");

GetOptions(
  "query=s" => \$query,
  "attr=s" => \@attr
);

index_project->searcher(
  query => $query,
  limit => 1000
)->each(sub{

  my $project = shift;
  say $project->{_id};

  for(@{ $project->{list} }){
    say "\t$_";
  }

});
