#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:fedora);
use Getopt::Long;

my($file);

GetOptions(
  "file=s" => \$file
);

open my $fh,"<:utf8",$file or die($!);
while(<$fh>){
  chomp;
  say $_;
  my $result = fedora()->listDatastreams(pid => $_);
  die($result->error) unless $result->is_ok;
  my $obj = $result->parse_content;
  
  #filter op dsid die beginnen met DS. (rest: bagit-bestanden)
  my @files = sort grep { $_->{dsid} =~ /^DS\.\d+$/ } @{ $obj->{datastream} };
  say "\t".$_->{label} for(@files);
  
}
close $fh;
