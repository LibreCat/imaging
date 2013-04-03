#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use Catmandu::FedoraCommons;
use Getopt::Long;
use DateTime::Format::Strptime;

my($username,$password,$file);
my $url = "http://localhost:4000/fedora";

GetOptions(
  "file=s" => \$file
);

my $fedora = Catmandu::FedoraCommons->new($url,"","");
my $date_formatter = DateTime::Format::Strptime->new(pattern => '%FT%T.%NZ');

open my $fh,"<:utf8",$file or die($!);
while(<$fh>){
  chomp;
  say $_;
  my $result = $fedora->getObjectProfile(pid => $_);
  die($result->error) unless $result->is_ok;
  my $obj = $result->parse_content;
  
  say "\tstatus archived: ".($obj->{objState} eq "A" ? "yes":"no");
  say "\tlast modified: ".$obj->{objLastModDate};
  my $d2 = $date_formatter->parse_datetime($obj->{objLastModDate});
  say "\tlast modified parsed: $d2";
  
}
close $fh;
