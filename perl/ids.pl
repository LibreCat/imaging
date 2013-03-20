#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(:all);

my $query = shift;
{
  my($offset,$limit,$total) = (0,1000,0);
  do{
    my $result = index_scan->search(
      query => $query,
      start => $offset,
      limit => $limit            
    );
    $total = $result->total;
    for my $scan(@{ $result->hits }){
      say $scan->{_id};
    }
    $offset += $limit;
  }while($offset < $total);
}
