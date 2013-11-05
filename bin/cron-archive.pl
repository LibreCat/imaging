#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);

use Imaging::Util qw(:files :data :lock);
use Imaging::Profile::BAG;
use Imaging::Scan qw(:all);
use Imaging qw(:all);

use File::Basename;
use IO::CaptureOutput qw(capture_exec);

my $pidfile;
INIT {
  #voer niet uit wanneer andere instantie van imaging-register.pl draait!
  $pidfile = "/tmp/imaging-register.pid";
  acquire_lock($pidfile);
}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}

my $this_file = basename(__FILE__);
say "$this_file started at ".local_time;

#opladen naar GREP
my @qa_control_ok = ();

index_scan->searcher(

  query => "status:\"qa_control_ok\"",
  limit => 1000

)->each(sub{

  push @qa_control_ok,$_[0]->{_id};

});


for my $scan_id(@qa_control_ok){

  my $scan = scans->get($scan_id);

  #archive_id ? => baseer je enkel op bag-info.txt (en NOOIT op naamgeving map, ook al heet die "archive-ugent-be-lkfjs" )
  my($archive_id,$is_new) = sync_baginfo($scan);
  if($is_new){
    say "\t\tnew archive_id: $archive_id";
  }

  #naamgeving map hoeft niet conform te zijn met archive-id (enkel bag-info.txt)
  my $grep_path = Catmandu->config->{'archive_site'}->{mount_incoming_bag}."/".basename($scan->{path});
  my $is_bag = Imaging::Profile::BAG->new()->test($scan->{path});
  my $command;

  #geen bag? Maak er dan een bag van
  if(!$is_bag){

    $command = drush_command('bt-bag',$scan->{path},$grep_path);
      
  }else{

    $command = "cp -R $scan->{path} $grep_path && rm -f $grep_path/__MANIFEST-MD5.txt";

  }

  say "command: $command";
  my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
  say "stderr:";
  say $stderr;
  say "stdout:";
  say $stdout;

  #damit: drush always returns 0, even in case of a failure!
  next if !$success || is_string($stderr);

  my $uid = data_at(Catmandu->config,"mounts.directories.owner.archive") || "fedora";
  my $gid = data_at(Catmandu->config,"mounts.directories.group.archive") || "fedora";
  my $rights = data_at(Catmandu->config,"mounts.directories.rights.archive") || "775";

  $command = "sudo chown -R $uid:$gid $grep_path && sudo chmod -R $rights $grep_path";
  ($stdout,$stderr,$success,$exit_code) = capture_exec($command);
  say $command;
  say "stderr:";
  say $stderr;
  say "stdout:";
  say $stdout;    

  next unless $success;

  say "scan archiving";

  my $log;
  ($scan,$log) = set_status($scan,status => "archiving");

  update_log($log,-1);
  update_scan($scan);

  say "scan record updated";

}

say "$this_file ended at ".local_time;
