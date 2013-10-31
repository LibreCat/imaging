#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use File::Path qw(rmtree);
use File::Basename;
use Imaging qw(:store);

#delete scans with status 'done'
index_scan->searcher(

  query => "status:done",
  limit => 1000

)->each(sub{

  my $scan = shift;

  say $scan->{_id};
  my $path = $scan->{path};
  say "\tpath: $path";
  if(!-d $path){
    say STDERR "\t$path does not exist";
    return
  }
  if(!-w dirname($path)){
    say STDERR "\tcannot write to parent directory ".dirname($path);
    return;
  }
  say "\tremoving $path";
  my $num_deleted = rmtree($path);
  if($num_deleted > 0){
    say "\t$path was successfully removed";
  }else{
    say "\tcould not delete $path";
  }

});
