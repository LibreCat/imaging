#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu qw(:load);
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use Imaging::Util qw(:data :files :lock);
use File::Basename qw();
use File::Path;
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use Time::Interval;

my($pidfile);
INIT {
	#voer niet uit wanneer andere instantie draait!
	$pidfile = "/tmp/imaging-cleanup.pid";
  acquire_lock($pidfile);
  #voer niet uit wanneer imaging-register.pl draait!
  my $pidfile_register = "/tmp/imaging-register.pid";
  check_lock($pidfile_register);
}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}
use Imaging qw(:all);

sub mount_conf {
  config->{mounts}->{directories};
}
sub upload_idle_time {
  state $upload_idle_time = do {
    my $config = config;
    my $time = data_at($config,"mounts.directories.ready.upload_idle_time");
    my $return;
    if($time){
      my %opts = ();
      my @keys = qw(seconds minutes hours days);
      foreach(@keys){
        $opts{$_} = is_string($time->{$_}) ? int($time->{$_}) : 0;
      }
      $return = convertInterval(%opts,ConvertTo => "seconds");
    }else{
      $return = 60;
    }
    $return;
  };
}
#how long before a warning is created?
#-1 means never
sub warn_after {
  state $warn_after = do {
    my $config = config;
    my $warn_after = data_at($config,"mounts.directories.ready.warn_after");
    my $return;
    if($warn_after){
      my %opts = ();
      my @keys = qw(seconds minutes hours days);
      foreach(@keys){
        $opts{$_} = is_string($warn_after->{$_}) ? int($warn_after->{$_}) : 0;
      }
      $return = convertInterval(%opts,ConvertTo => "seconds");
    }else{
      $return = -1;
    }
    $return;
  };
}
sub do_warn {
  my $scan = shift;
  my $warn_after = warn_after();
  if($warn_after < 0){
    return 1;
  }else{
    my $mtime = mtime_latest_file($scan->{path});
    return ( $mtime + $warn_after - time ) < 0;
  }
}
#how long before the scan is deleted?
#-1 means never
sub delete_after {
  state $delete_after = do {
    my $config = config;
    my $delete_after = data_at($config,"mounts.directories.ready.delete_after");
    my $return;
    if($delete_after){
      my %opts = ();
      my @keys = qw(seconds minutes hours days);
      foreach(@keys){
        $opts{$_} = is_string($delete_after->{$_}) ? int($delete_after->{$_}) : 0;
      }
      $return = convertInterval(%opts,ConvertTo => "seconds");
    }else{
      $return = -1;
    }
    $return;
  };
}
sub do_delete {
  my $scan = shift;
  my $delete_after = delete_after();
  my $warn_after = warn_after();  
  if($delete_after < 0){
    return 0;
  }else{
    my $mtime = mtime_latest_file($scan->{path});
    return ( $mtime + $warn_after + $delete_after - time ) < 0;
  }
}
sub delete_scan_data {
  my $scan = shift;
  try{
    rmtree($scan->{path});
  }catch{
    say STDERR $_;
  };
}
sub file_seconds_old {
  time - mtime(shift);
}
sub file_is_busy {
  file_seconds_old(shift) <= upload_idle_time();
}



my $mount_conf = mount_conf;
my $scans = scans;

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

#stap 1: zoek scans

say "";
say "looking for scans in ".$mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready};

my @scans_ready = ();

users->each(sub{

    my $user = $_[0];

    say "  ".$user->{_id};

    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};

    if(! -d $ready ){
      say "    directory $ready does not exist";
      return;
    }elsif(!getpwnam($user->{login})){
      say "    user $user->{login} does not exist";
      return;
    }
    try{
      local(*CMD);
      open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d 2> /dev/null |" or die($!);
      while(my $dir = <CMD>){
        chomp($dir);    
        
        if(!(-d -r $dir)){
          say "    $dir: not readable";
          next;
        }
        #wacht tot __FIXME.txt verwijderd is
        elsif(-f "$dir/__FIXME.txt"){
          say "    $dir: to be fixed";
          next;
        }
        #wacht totdat er lange tijd niets met de map is gebeurt!!
        elsif(file_is_busy($dir)){
          say "    $dir: busy";
          next;
        }
        
        #voeg toe aan te verwerken directories
        push @scans_ready,$dir; 
      }
      close CMD;   
    }catch{
      chomp($_);
      say STDERR $_;
    };

});

my @delete = ();
my @warn = ();
say "inspecting directories for warning or removal";
foreach my $scan_dir(@scans_ready){
  my $basename = File::Basename::basename($scan_dir);
  
  my $scan = scans()->get($basename);
  if(!$scan){
    say "  $scan_dir: not yet added to database";
    next;
  }elsif(do_delete($scan)){
    say "  $scan_dir: added to list for removal";
    #voor later
    next;
    push @delete,$scan->{_id};
  }elsif(do_warn($scan)){
    say "  $scan_dir: added to list for warning";    
    push @warn,$scan->{_id};
  }else{
    say "  $scan_dir: nothing to do";
  }
};
say "executing removal.." if @delete;
foreach my $id(@delete){
  my $scan = scans()->get($id);

  delete_scan_data($scan);
  scans()->delete($id);
  index_scan()->delete($id);  

  say $scan->{path}.": deleted";
}
say "adding warnings.." if @warn;
foreach my $id(@warn){
  my $scan = scans()->get($id);
  $scan->{warnings} = [{
    datetime => Time::HiRes::time,
    text => "Deze map heeft de tijdslimiet op validatie niet gehaald, en zal binnenkort verwijderd worden",
    username => "-"
  }];   
  scans()->add($scan);
  say $scan->{path}.": warning added";
}

index_scan()->commit;

say "";
say "$this_file ended at ".local_time;
