#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(:store);

say "indexing scans:";
scans->each(sub{
  say $_[0]->{_id};
  scan2index($_[0]);
});
say "indexing logs:";
logs->each(sub{
  say $_[0]->{_id};
  log2index($_[0]);
});
say "indexing projects:";
projects->each(sub{
  say $_[0]->{_id};
  project2index($_[0]);
});

index_scan()->commit();
index_log()->commit();
index_project()->commit();
