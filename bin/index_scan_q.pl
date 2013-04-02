#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:all);
use Getopt::Long;


my($file,@attr) = ("/dev/stdin");

GetOptions(
  "file=s" => \$file,
  "attr=s" => \@attr
);

open my $fh,"<:encoding(UTF-8)",$file or die($!);
while(my $query = <$fh>){
  chomp $query;
  say $query;
  my($offset,$limit,$total) = (0,1000,0);
  do{
    my $result = index_scan->search(
      query => $query,
      start => $offset,
      limit => $limit            
    );
    $total = $result->total;
    for my $scan(@{ $result->hits }){
      print "\t".$scan->{_id};
      for(@attr){
        print " ".($scan->{$_} // "<not defined>");
      }
      print "\n";
    }
    $offset += $limit;
  }while($offset < $total);
}
close $fh;
