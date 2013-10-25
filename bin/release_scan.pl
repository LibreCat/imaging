#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Imaging qw(:store);
use Getopt::Long;

my($id);

GetOptions(
  "id=s" => \$id,
);

my $scan = scans()->get($id);
exit 1 unless $scan;

delete $scan->{$_} for qw(busy asset_id);
update_scan($scan);
