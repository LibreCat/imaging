#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu::Sane;
use Imaging qw(:fedora);
use Getopt::Long;
use DateTime::Format::Strptime;

my($file);

GetOptions(
  "file=s" => \$file
);

my $date_formatter = DateTime::Format::Strptime->new(pattern => '%FT%T.%NZ');

open my $fh,"<:utf8",$file or die($!);
while(<$fh>){
  chomp;
  say $_;
  my $result = fedora()->getObjectProfile(pid => $_);
  die($result->error) unless $result->is_ok;
  my $obj = $result->parse_content;
  
  say "\tstatus archived: ".($obj->{objState} eq "A" ? "yes":"no");
  say "\tlast modified: ".$obj->{objLastModDate};
  my $d2 = $date_formatter->parse_datetime($obj->{objLastModDate});
  say "\tlast modified parsed: $d2";
  
}
close $fh;
