#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Imaging qw(:all);

scans->each(sub{
  say $_[0]->{_id};
  scan2index($_[0]);
});
