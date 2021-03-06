#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use Try::Tiny;
use File::Temp qw(tempfile);
use File::Copy qw(move);
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

#mv 02_processed 02_imaging/registered of 02_imaging/processed

#itereer over scans, verplaats status_history naar tabel 'logs', en wijzig 'path' =>  TODO: effectieve create van 02_registered en 03_processed + test of paden nog werken
open $fh,"<:utf8",$filename or die($!);
while(my $scan_id = <$fh>){
  chomp $scan_id;
  say $scan_id;
  my $scan = scans->get($scan_id);

  #verplaats status_history
  my $log = {
    _id => $scan_id,
    user_id => $scan->{user_id},
    status_history => $scan->{status_history},
    datetime_last_modified => $scan->{datetime_last_modified}
  };
  delete $scan->{status_history};
  
  #verplaats 'path'  
  if($scan->{path} =~ /02_processed/){

    my $old_path = $scan->{path};
    #02_processed bestaat niet meer, wel 02_imaging/registered
    $scan->{path} =~ s/02_processed/02_imaging\/registered/;
    
    #<> 'registered'? Verplaatsen naar 02_imaging/processed
    if($scan->{status} ne "registered"){

      my $new_path = $scan->{path};
      $new_path =~ s/registered/processed/;
      if(-d $scan->{path}){
        unless( move($scan->{path},$new_path) ){
          say STDERR "error while trying to move ".$scan->{path}." to $new_path, aborting..";
          say STDERR $!;
          exit(1);
        }
      }
      $scan->{path} = $new_path;

    }

    say "\tpath moved from $old_path to $scan->{path}";
  }


  #databank
  scans()->add($scan);
  logs()->add($log);

  say "\tlog moved to logs";
  
  #index
  my $scan_doc = scan2doc($scan);
  my $log_docs = log2docs($log);
  index_log()->add($_) for @$log_docs;
  index_log()->commit();
  index_scan()->add($scan_doc);
}
index_log()->commit();
index_scan()->commit();
close $fh;
