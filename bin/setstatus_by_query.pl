#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Imaging qw(:all);
use Catmandu::Sane;
use Getopt::Long;

sub usage {
  return "usage: $0 --status <status> --query <query>\n";
}

my($query,$status);

GetOptions(
  "query=s" => \$query,
  "status=s" => \$status
);

defined($status) || die(usage());
defined($query) || die(usage());

my @ids = ();

index_scan->searcher(
  query => $query,
  limit => 1000           
)->each(sub{

  push @ids,$_[0]->{_id};

});

for my $id(@ids){
  my $scan = scans->get($id);
  next if !$scan;
  say $scan->{_id};
  my $log;
  ($scan,$log) = set_status($scan,status => $status);
  update_scan($scan);
  update_status($log,-1);
}
