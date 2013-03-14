#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu;
use Dancer qw(:script);
use Catmandu::Sane;
use File::Path qw(rmtree);
use Cwd;

BEGIN {
   
  #load configuration
  my $appdir = Cwd::realpath(
      dirname(dirname(
          Cwd::realpath( __FILE__)
      ))
  );
  Dancer::Config::setting(appdir => $appdir);
  Dancer::Config::setting(public => "$appdir/public");
  Dancer::Config::setting(confdir => $appdir);
  Dancer::Config::setting(envdir => "$appdir/environments");
  Dancer::Config::load();
  Catmandu->load($appdir);

}

use Dancer::Plugin::Imaging::Routes::Utils;


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
