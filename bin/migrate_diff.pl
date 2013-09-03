#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(:all);
use Catmandu::Store::DBI;
use Data::Compare;

my $old_store = Catmandu::Store::DBI->new(
  data_source => "dbi:mysql:database=imaging_back",
  username => "imaging",
  password => "imaging",
  bags => {
    projects => { serialization_format => "messagepack" },
    scans => { serialization_format => "messagepack" },
    users => { serialization_format => "messagepack" },
    logs => { serialization_format => "messagepack" }
  }
);

$old_store->bag("scans")->each(sub{
  my $old_scan = shift;
  my $new_scan = scans()->get($old_scan->{_id});
  my $new_log = logs()->get($old_scan->{_id});
  my $scan_equal = Compare($old_scan,$new_scan,{ ignore_hash_keys => [qw(status_history path)] });
  my $log_equal = Compare($old_scan->{status_history},$new_log->{status_history});
  say $old_scan->{_id}.": scan ".($scan_equal ? "equal":"not equal").", log equal: ".($log_equal ? "equal":"not equal");
});

index_scan()->searcher(query => "-status:done AND -status:incoming*")->each(sub{
  my $scan = shift;
  say $scan->{path}." : ".(-d $scan->{path} ? "exists":"does not exist");
});
