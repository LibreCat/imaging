#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu qw(:load);
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use Imaging::Util qw(:data :files);
use Imaging::Profiles;
use Imaging::Dir::Info;
use List::MoreUtils;
use File::Basename qw();
use File::Path;
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use Time::Interval;
use File::Pid;
our($a,$b);

my($pid,$pidfile);
BEGIN {
	#voer niet uit wanneer andere instantie draait!
	$pidfile = "/tmp/imaging-check.pid";
	$pid = File::Pid->new({
		file => $pidfile
	});
	if(-f $pid->file && $pid->running){
		die("Cannot run while other instance is running\n");
	}
	#plaats lock
	say "this process id: $$";
  -f $pidfile && ($pid->remove or die("could not remove lockfile $pidfile!"));
  $pid->pid($$);
	$pid->write or die("unable to place lock!");
}
END {
    #verwijder lock
    $pid->remove if $pid;
}
use Imaging qw(:all);

sub profiles_conf {
  config->{profiles} ||= {};
}
sub profile_detector {
  state $r = Imaging::Profiles->new(
    list => config->{profile_detector}->{list} || []
  );
}
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


#voer niet uit wanneer imaging-register.pl draait!

my $pidfile_register = "/tmp/imaging-register.pid";
my $pid_register = File::Pid->new({
  file => $pidfile_register
});
if(-f $pid_register->file && $pid_register->running){
  die("Cannot run while registration is running\n");
}

my $mount_conf = mount_conf;
my $scans = scans;

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

#stap 1: zoek scans
# 1. lijst mappen
# 2. Map staat niet in databank: voeg nieuw record toe
# 3. Map staat wel in databank:
#   3.1. staat __FIXME.txt in de map? Doe dan niets
#   3.2. check hoe oud de nieuwste file in de map is. Indien nog niet zo lang geleden, wacht dan

say "looking for scans in ".$mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."\n";

my @scan_ids_ready = ();

users->each(sub{

    my $user = $_[0];

    say $user->{_id};

    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};

    if(! -d $ready ){
      say "directory $ready does not exist";
      return;
    }elsif(!getpwnam($user->{login})){
      say "user $user->{login} does not exist";
      return;
    }
    try{
      local(*CMD);
      open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d 2> /dev/null |" or die($!);
      while(my $dir = <CMD>){
        chomp($dir);    
        
        if(!(-d -r $dir)){
          say "directory $dir is not readable, so ignoring..";
          next;
        }
        #wacht tot __FIXME.txt verwijderd is
        elsif(-f "$dir/__FIXME.txt"){
          say "directory '$dir' has to be fixed, so ignoring..";
          next;
        }
        #wacht totdat er lange tijd niets met de map is gebeurt!!
        elsif(file_is_busy($dir)){
          say "directory '$dir' probably busy";
          next;
        }

        my $basename = File::Basename::basename($dir);
        my $scan = $scans->get($basename);

        #map komt nog niet voor in databank
        if(!is_hash_ref($scan)){

          my $mtime = mtime_latest_file($dir);

          say "adding new record $basename";
          $scan = {
            _id => $basename,
            name => undef,
            path => $dir,
            status => "incoming",
            status_history => [{
              user_login => $user->{login},
              status => "incoming",
              datetime => Time::HiRes::time,
              comments => ""
            }],
            check_log => [],
            user_id => $user->{id},
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

          #update scans, index_scan en index_log
          update_scan($scan);
          update_status($scan);
        }

        #voeg toe aan te verwerken directories
        push @scan_ids_ready,$scan->{_id}; 
      }
      close CMD;   
    }catch{
      chomp($_);
      say STDERR $_;
    };

});

#stap 2: zijn er scans die opnieuw in het systeem geplaatst moeten worden?
#regel: indien $scan->{path} niet meer bestaat, dan wordt dit toegepast!
for my $scan_id(@scan_ids_ready){

  my $scan = $scans->get($scan_id);

  #opgelet: reeds gecontroleerde scans met status ~ incoming vallen niet onder deze regeling!
  next if ( (-d $scan->{path}) || ($scan->{status} =~ /incoming/o) );

#  $scan->{status} = "incoming";
#  push @{ $scan->{status_history} },{
#    user_login => "-",
#    status => $scan->{status},
#    datetime => Time::HiRes::time,
#    comments => "Scan directory opnieuw in systeem"
#  };
#  $scan->{datetime_last_modified} = Time::HiRes::time;
  set_status($scan,status => "incoming");
  update_scan($scan);
  update_status($scan,-1);

}

#stap 3: zijn er scandirectories die hier al te lang staan?
my @delete = ();
my @warn = ();
#foreach my $scan_id(@scan_ids_ready){
#    my $scan = $scans->get($scan_id);
#    if(do_delete($scan)){
#        say "ah too late man!";
#        #voor later
#        next;
#        say "nothing too see here!";
#
#        push @delete,$scan->{_id};
#    }elsif(do_warn($scan)){
#        say "ah a warning!";
#        push @warn,$scan->{_id};
#    }
#};
#foreach my $id(@delete){
#    my $scan = $scans->get($id);
#    say "ah no! You're deleting things!";
#    delete_scan_data($scan);
#    $scans->delete($id);
#}
#foreach my $id(@warn){
#    my $scan = $scans->get($id);
#    $scan->{warnings} = [{
#        datetime => Time::HiRes::time,
#        text => "Deze map heeft de tijdslimiet op validatie niet gehaald, en zal binnenkort verwijderd worden",
#        username => "-"
#    }];   
#    $scans->add($scan);
#}

#stap 4: doe check -> filter lijst van scan_ids_ready op mappen die gecontroleerd moeten worden:
# 1. mappen die nog geen controle zijn gepasseerd, worden gecontroleerd
# 2. mappen die wel eens gecontroleerd zijn, maar ongewijzigd sindsdien, worden niet gecontroleerd
sub get_package {
  my($class,$args)=@_;
  require_package($class)->new(%$args);
}
my @scan_ids_test = ();
foreach my $scan_id(@scan_ids_ready){

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

foreach my $scan_id(@scan_ids_test){

  my $scan = $scans->get($scan_id);

  $scan->{busy} = 1;

  say "checking $scan_id at $scan->{path}";

  #get profile
  my $profile_id = profile_detector->get_profile($scan->{path});
  my $profile;

  #lijst bestanden
  my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});

  #initialise check_log
  $scan->{check_log} = [];

  if(!is_string($profile_id)){

    $scan->{check_log} = ["map voldoet aan geen van de bestaande profielen"];

  }elsif(
    !($profile = profiles_conf->{$profile_id})
  ){
    
    say STDERR "strange, profile_id '$profile_id' is defined, but no profile configuration could be found";
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

#    $scan->{status} = $num_fatal > 0 ? "incoming_error":"incoming_ok";
#    my $status_history_object = {
#      user_login => "-",
#      status => $scan->{status},
#      datetime => Time::HiRes::time,
#      comments => ""
#    };
#    push @{ $scan->{status_history} },$status_history_object;

    set_status($scan,status => ($num_fatal > 0 ? "incoming_error":"incoming_ok"));

  }

  $scan->{datetime_last_modified} = Time::HiRes::time;

  #update scans, index_scan en index_log
  update_scan($scan);
  update_status($scan,-1);

}

#check of alle incoming_* er nog staan
#gevaarlijk voor oude records die terug naar incoming moeten, en dan plotseling verwijderd worden!
#say "checking if all incoming are still there..";
#{
#    my $total_incoming = 0;
#    my($offset,$limit) = (0,1000);
#
#    do{
#
#        my $result = index_scan->search(query => "status:incoming*",limit => $limit,offset=>$offset);
#        $total_incoming = $result->total();
#
#        foreach my $hit(@{ $result->hits }){
#            my $scan = scans->get($hit->{_id});            
#            if(!-d $scan->{path}){
#                say "\t".$scan->{_id}." removed or renamed";
#                index_scan->delete($scan->{_id});
#                index_scan->commit;
#                index_log->delete_by_query(query => "scan_id:\"".$scan->{_id}."\"");
#                index_log->commit;
#                scans->delete($scan->{_id});
#            }
#        }
#        $offset += $limit;
#    }while($offset < $total_incoming);
#}

say "$this_file ended at ".local_time;