#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Catmandu::Sane;
use File::Path qw(rmtree);
use File::Basename;
use Imaging qw(:all);

my($offset,$limit,$total) = (0,1000,0);
do{

  my $result = index_scan->search(
    query => "status:done",
    start => $offset,
    limit => $limit            
  );

  $total = $result->total;

  for my $scan(@{ $result->hits }){
    say $scan->{_id};
    my $path = $scan->{path};
    say "\tpath: $path";
    if(!-d $path){
      say STDERR "\t$path does not exist";
      next;
    }
    if(!-w dirname($path)){
      say STDERR "\tcannot write to parent directory ".dirname($path);
      next;
    }
    say "\tremoving $path";
    my $num_deleted = rmtree($path);
    if($num_deleted > 0){
      say "\t$path was successfully removed";
    }else{
      say "\tcould not delete $path";
    }
  }
  $offset += $limit;

}while($offset < $total);

say "total: $total";
