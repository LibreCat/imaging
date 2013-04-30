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
  
  index_scan->searcher(

    query => $query,
    limit => 1000

  )->each(sub{

    my $scan = shift;
    print "\t".$scan->{_id};
    for(@attr){
      print " ".($scan->{$_} // "<not defined>");
    }
    print "\n";

  });
}
close $fh;
