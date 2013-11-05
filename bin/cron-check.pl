#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load);
use Catmandu::Util qw(require_package :is :array);
use Imaging::Util qw(:data :files :lock);
use Imaging::Profiles;
use Imaging::Dir::Info;
use List::MoreUtils;
use File::Basename;
use File::Path;
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use Time::Interval;
our($a,$b);

my($pidfile);
INIT {
	#voer niet uit wanneer andere instantie draait!
	$pidfile = "/tmp/imaging-check.pid";
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

sub profiles_conf {
  Catmandu->config->{profiles} ||= {};
}
sub profile_detector {
  state $r = Imaging::Profiles->new(
    list => Catmandu->config->{profile_detector}->{list} || []
  );
}
sub upload_idle_time {
  state $upload_idle_time = do {
    my $config = Catmandu->config;
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
sub file_seconds_old {
  time - mtime(shift);
}
sub file_is_busy {
  file_seconds_old(shift) <= upload_idle_time();
}

my $mount_conf = mount_conf;
my $scans = scans;

my $this_file = basename(__FILE__);
say "$this_file started at ".local_time."\n";

#stap 1: zoek scans
# 1. lijst mappen
# 2. Map staat niet in databank: voeg nieuw record toe
# 3. Map staat wel in databank:
#   3.1. staat __FIXME.txt in de map? Doe dan niets
#   3.2. check hoe oud de nieuwste file in de map is. Indien nog niet zo lang geleden, wacht dan

say "looking if users have scans in ".$mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready};

my @scans_ready = ();

users->each(sub{

    my $user = $_[0];

    say " ".$user->{_id};

    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};

    if(! -d $ready ){
      say "  directory $ready does not exist";
      return;
    }elsif(!getpwnam($user->{login})){
      say "  user $user->{login} does not exist";
      return;
    }
    try{
      local(*CMD);
      open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d 2> /dev/null |" or die($!);
      while(my $dir = <CMD>){
        chomp($dir);    
        
        if(!(-d -r $dir)){
          say "  directory $dir is not readable, so ignoring..";
          next;
        }
        #wacht tot __FIXME.txt verwijderd is
        elsif(-f "$dir/__FIXME.txt"){
          say "  directory '$dir' has to be fixed, so ignoring..";
          next;
        }
        #wacht totdat er lange tijd niets met de map is gebeurt!!
        elsif(file_is_busy($dir)){
          say "  directory '$dir' probably busy";
          next;
        }

        my $basename = basename($dir);
        my $scan = $scans->get($basename);

        #map komt nog niet voor in databank
        if(!is_hash_ref($scan)){

          my $mtime = mtime_latest_file($dir);

          say "  adding new record $basename";
          my $log;
          $scan = {
            _id => $basename,
            name => undef,
            path => $dir,
            check_log => [],
            user_id => $user->{_id},
            #mtime van de nieuwste file in deze directory (!= mtime(dir))
            datetime_directory_last_modified => $mtime,
            #wanneer heeft het systeem de status van dit record voor het laatst aangepast
            datetime_last_modified => Time::HiRes::time,
            #wanneer heeft het systeem de directory voor het eerst zien staan
            datetime_started => Time::HiRes::time,
            project_id => undef,
            metadata => [],
            comments => [],
            warnings => [],
            #default busy!
            busy => 1,
            #mediamosa
            #asset_id => "lkfjkfj25df25df"
            #grep
            #archive_id => "archive.ugent.be:lkzejrzlrj-lfkjslfjsf"
          };

          ($scan,$log) = set_status($scan,status => "incoming",user_login => $user->{login});

          #update scans, index_scan en index_log
          update_log($log);
          update_scan($scan);
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

say "looking for updates for old scans..";
#stap 2: zijn er scans die opnieuw in het systeem geplaatst moeten worden?
#regel: indien $scan->{path} niet meer bestaat, dan wordt dit toegepast!
for my $scan_dir(@scans_ready){
  
  my $scan_id = basename($scan_dir);
  my $scan = $scans->get($scan_id);

  #opgelet: reeds gecontroleerde scans met status ~ incoming vallen niet onder deze regeling!
  next if -d $scan->{path};
  
  #edit path
  say " resetting path from ".$scan->{path}." to $scan_dir";
  $scan->{path} = $scan_dir;
  $scan->{warnings} = [];

  my $log;
  ($scan,$log) = set_status($scan,status => "incoming");
  update_log($log,-1);
  update_scan($scan);

}

#stap 3: doe check -> filter lijst van scan_ids_ready op mappen die gecontroleerd moeten worden:
# 1. mappen die nog geen controle zijn gepasseerd, worden gecontroleerd
# 2. mappen die wel eens gecontroleerd zijn, maar ongewijzigd sindsdien, worden niet gecontroleerd
sub get_package {
  my($class,$args)=@_;
  require_package($class)->new(%$args);
}
say "checking which incoming scans to test..";
my @scan_ids_test = ();
foreach my $scan_dir(@scans_ready){

  my $scan_id = basename($scan_dir);
  my $scan = $scans->get($scan_id);

  #check nieuwe directories (opgelet: ook record zonder profile_id onder)
  if(
    array_includes([qw(incoming)],$scan->{status})      
  ){
    #oud record zonder profile_id enkel controleren indien iets gewijzigd
    if(
      is_array_ref($scan->{check_log}) &&
      scalar(@{ $scan->{check_log} }) > 0
    ){ 

      if(
        mtime_latest_file($scan->{path}) > $scan->{datetime_last_modified}
      ){ 
        push @scan_ids_test,$scan->{_id};
      }

    }
    #nieuw record
    else{
      push @scan_ids_test,$scan->{_id};
    }

  }
  #check slechte en goede indien iets gewijzigd sinds laatste check
  elsif(
    array_includes(["incoming_error","incoming_ok"],$scan->{status}) &&
    mtime_latest_file($scan->{path}) > $scan->{datetime_last_modified}
  ){
    push @scan_ids_test,$scan->{_id};
  }

};
if(scalar(@scan_ids_test)){
  say "starting test";
}else{
  say "no scans to test found";
}
foreach my $scan_id(@scan_ids_test){

  my $scan = $scans->get($scan_id);
  my $log;

  $scan->{busy} = 1;
  #report that this scan is busy
  $scans->add($scan);  

  say " checking $scan_id at $scan->{path}";

  #get profile
  my $profile_id = profile_detector->get_profile($scan->{path});
  my $profile;

  #lijst bestanden
  my $dir_error;
  my $dir_info;
  try{
    $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});
  }catch{
    $dir_error = $_;    
  };
  if($dir_error){
    say "  error while trying to list files in ".$scan->{path}.": $dir_error";
    next;
  }

  #initialise check_log
  $scan->{check_log} = [];

  if(!is_string($profile_id)){

    $scan->{check_log} = ["map voldoet aan geen van de bestaande profielen"];

  }elsif(
    !($profile = profiles_conf->{$profile_id})
  ){
    
    say "  strange, profile_id '$profile_id' is defined, but no profile configuration could be found";
    next;

  }else{

    #registreer onder welk profiel deze scan valt
    $scan->{profile_id} = $profile_id;

    #acceptatie valt niet af te leiden uit het bestaan van foutboodschappen, want niet alle testen zijn 'fatal'
    my $num_fatal = 0;
    
    foreach my $test(@{ $profile->{packages} }){
      my $ref = get_package($test->{class},$test->{args});
      $ref->dir_info($dir_info);        
      my($success,$errors) = $ref->test();

      push @{ $scan->{check_log} }, @$errors if !$success;
      if(!$success){
        if($test->{on_error} eq "stop"){
          $num_fatal = 1;
          last;
        }elsif($ref->is_fatal){
          $num_fatal++;
        }
      }
    }

    ($scan,$log) = set_status($scan,status => ($num_fatal > 0 ? "incoming_error":"incoming_ok"));

  }

  $scan->{datetime_last_modified} = Time::HiRes::time;

  #TODO!!!
  $scan->{busy} = 0;
  #update scans, index_scan en index_log
  update_log($log,-1) if $log;
  update_scan($scan);

}

say "\n$this_file ended at ".local_time;
