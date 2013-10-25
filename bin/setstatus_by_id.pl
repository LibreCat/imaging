#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(:store);
use Getopt::Long;

sub usage {
  "usage: $0 --status <status> [--file <file>]\n";
}

my($file,$status);

GetOptions(
  "file=s" => \$file,
  "status=s" => \$status
);

defined($status) || die(usage());
$file = "/dev/stdin" unless defined $file;

open my $fh,"<:encoding(UTF-8)",$file or die($!);

my $id;
while($id = <$fh>){
  chomp $id;
  my $scan = scans->get($id);
  next if !$scan;
  say $scan->{_id}." : ".$scan->{status}." => $status";
  my $log;
  ($scan,$log) = set_status($scan,status => $status);
  update_scan($scan);
  update_log($log,-1);
}

close $fh;
