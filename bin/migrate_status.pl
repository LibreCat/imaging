#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use Try::Tiny;
use File::Temp qw(tempfile);
use Imaging qw(:all);

#write all identifiers to a temporary file
my($fh,$filename) = tempfile(UNLINK => 1);
die("could not create temporary file\n") unless $fh;
binmode($fh,":utf8");
say "writing all ids to temporary file $filename";
scans->each(sub{
  say $fh $_[0]->{_id};
});
close $fh;

#itereer over scans, verplaats status_history naar tabel 'logs'
open $fh,"<:utf8",$filename or die($!);
while(my $scan_id = <$fh>){
  chomp $scan_id;
  say $scan_id;
  my $scan = scans->get($scan_id);
  my $log = {
    _id => $scan_id,
    user_id => $scan->{user_id},
    status_history => $scan->{status_history},
    datetime_last_modified => $scan->{datetime_last_modified}
  };
  delete $scan->{status_history};

  #databank
  scans()->add($scan);
  logs()->add($log);
  
  #index
  my $scan_doc = scan2doc($scan);
  my $log_docs = log2docs($log);
  index_scan()->add($scan_doc);
  index_log()->add($_) for @$log_docs;
}
index_scan()->commit();
index_log()->commit();
close $fh;
