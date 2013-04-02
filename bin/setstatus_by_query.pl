#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Imaging qw(:all);
use Catmandu::Sane;
use Getopt::Long;

sub usage {
  say "usage: $0 --status <status> --query <query>";
}

my($query,$status);

GetOptions(
  "query=s" => \$query,
  "status=s" => \$status
);

defined($status) || die(usage());
defined($query) || die(usage());

my @ids = ();

my($offset,$limit,$total) = (0,1000,0);
do{

  my $result = index_scan->search(
    query => $query,
    start => $offset,
    limit => $limit            
  );
  $total = $result->total;
  for my $scan(@{ $result->hits }){
    push @ids,$scan->{_id};
  }
  $offset += $limit;

}while($offset < $total);

for my $id(@ids){
  my $scan = scans->get($id);
  next if !$scan;
  say $scan->{_id};

  set_status($scan,status => $status);
  update_scan($scan);
  update_status($scan,-1);
}
