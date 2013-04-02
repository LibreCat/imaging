#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu;
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);
use File::Basename qw();
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use IO::CaptureOutput qw(capture_exec);

BEGIN {
   
  #load configuration
  my $appdir = Cwd::realpath(
    dirname(dirname(
      Cwd::realpath(__FILE__)
    ))
  );
  Dancer::Config::setting(appdir => $appdir);
  Dancer::Config::setting(public => "$appdir/public");
  Dancer::Config::setting(confdir => $appdir);
  Dancer::Config::setting(envdir => "$appdir/environments");
  Dancer::Config::load();
  Catmandu->load($appdir);
}
use Imaging qw(:all);


#variabelen
sub mount_conf {
  config->{mounts}->{directories} ||= {};
}

my $mount_conf = mount_conf();
my $dir_processed = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed};


while(my $id = <STDIN>){
  chomp $id;
  say $id;

  my $scan = scans->get($id);

  if(!$scan){
    say "\t$id not found";
    next;
  }
  if($scan->{profile_id} ne "NARA"){
    say "\t$id has not a NARA profile";
    next;
  }
  if($scan->{path} !~ /^$dir_processed/o){
    say "\t$scan->{path} not in directory $dir_processed";
    next;
  }
  if($scan->{status} ne "registered"){
    say "\tinvalid status $scan->{status}";
    next;
  }
  

  my $command = sprintf(config->{mediamosa}->{drush_command}->{mmnara},$scan->{path});
  say "\t$command";

  next;

  my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
  say "\tstderr: $stderr";
  say "\tstdout: $stdout";

  if(!$success){

    say "\toperation failed";

  }elsif($stdout =~ /new asset id: (\w+)\n/m){

    say "\tasset_id found:$1";
    $scan->{busy} = 1;
    $scan->{asset_id} = $1;
    $scan->{datetime_last_modified} = Time::HiRes::time;
    update_scan($scan);

  }else{

    say "\tcannot find asset_id in response";

  }

  update_scan($scan);
  update_status($scan,-1);    
}
