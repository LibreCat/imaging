#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use Catmandu::FedoraCommons;
use Getopt::Long;

my($username,$password,$file);
my $url = "http://localhost:4000/fedora";

GetOptions(
  "file=s" => \$file
);

my $fedora = Catmandu::FedoraCommons->new($url,"","");

open my $fh,"<:utf8",$file or die($!);
while(<$fh>){
  chomp;
  say $_;
  my $result = $fedora->listDatastreams(pid => $_);
  die($result->error) unless $result->is_ok;
  my $obj = $result->parse_content;
  
  #filter op dsid die beginnen met DS. (rest: bagit-bestanden)
  my @files = sort grep { $_->{dsid} =~ /^DS\.\d+$/ } @{ $obj->{datastream} };
  say "\t".$_->{label} for(@files);
  
}
close $fh;
