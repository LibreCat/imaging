#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);

use Imaging::Util qw(:files :data :lock);
use Imaging::Dir::Info;
use Imaging::Bag::Info;
use Imaging::Profile::BAG;
use Imaging::Meercat qw(:all);
use Imaging::Scan qw(:all);
use Imaging qw(:all);

use File::Basename;
use File::Copy qw(copy move);
use File::Spec;
use Digest::MD5 qw(md5_hex);
use Time::HiRes;
use English '-no_match_vars';
use Archive::BagIt;
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

#stap 1: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_registered (en maak hierbij manifest)
my @incoming_ok = ();

index_scan->searcher(

  query => "status:\"incoming_ok\"",
  limit => 1000

)->each(sub{

  my $scan = shift;
  if(!(-f $scan->{path}."/__FIXME.txt")){
    push @incoming_ok,$scan->{_id};
  }

});

say "registering incoming_ok";

my $mount_conf = mount_conf();
my $dir_registered = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{registered};

if(!-w $dir_registered){

  #not recoverable: aborting
  say "\tcannot write to $dir_registered";    

}else{

  foreach my $id (@incoming_ok){
    my $scan = scans()->get($id);    

    say "\tscan $id:";

    if(!-w dirname($scan->{path})){

      say "\t\tcannot move $scan->{path} from parent directory";
      #not recoverable: aborting
      next;

    }         

    #check: tussen laatste cron-check en registratie kan de map nog aangepast zijn..
    my $mtime_latest_file = mtime_latest_file($scan->{path});
    if($mtime_latest_file > $scan->{datetime_last_modified}){
      say "\t\tis changed since last check, I'm sorry! Aborting..";
      #not recoverable: aborting
      next;
    }

    #check BAGS!
    if($scan->{profile_id} eq "BAG"){
      say "\t\tvalidating as bagit";
      my @errors = ();
      my $bag = Archive::BagIt->new();
      my $success = $bag->read($scan->{path});        
      if(!$success){
        push @errors,@{ $bag->_error };
      }elsif(!$bag->valid){
        push @errors,@{ $bag->_error };
      }
      if(scalar(@errors) > 0){
        say "\t\tfailed";
        my $log;
        ($scan,$log) = set_status($scan,status => "incoming_error");
        $scan->{check_log} = \@errors;

        update_log($log,-1);
        update_scan($scan);

        #see you later!
        #not recoverable: aborting
        next;
      }else{
        say "\t\tsuccessfull";
      }
    }
    
    
    #ok, tijdelijk toekennen aan uitvoerende gebruiker, opdat niemand kan tussenkomen..
    #vergeet zelfde rechten niet toe te kennen aan bovenliggende map (anders kan je verwijderen..)
    my $this_uid = getpwuid($UID);
    my $this_gid = getgrgid($EGID);

    my $uid = data_at(Catmandu->config,"mounts.directories.owner.registered") || $this_uid;
    my $gid = data_at(Catmandu->config,"mounts.directories.group.registered") || $this_gid;
    my $rights = data_at(Catmandu->config,"mounts.directories.rights.registered") || "775";

    
    my($uname) = getpwnam($uid);
    if(!is_string($uname)){
      say "\t\t$uid is not a valid user name";
      #not recoverable: aborting
      next;
    }
    say "\t\tchanging ownership of '$scan->{path}' to $this_uid:$this_gid";

    {

      my $command = "sudo chown -R $this_uid:$this_gid $scan->{path} && sudo chmod -R 770 $scan->{path}";
      my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
      if(!$success){
        say "\t\tcannot change ownership: $stderr";
        #not recoverable: aborting
        next;
      }

    }

    my $old_path = $scan->{path};
    my $new_path = "$dir_registered/".basename($old_path);   


    #maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)            
    say "\t\tcreating __MANIFEST-MD5.txt";   
    my $path_manifest = $scan->{path}."/__MANIFEST-MD5.txt";
    if(-f $path_manifest){
      if(!unlink($path_manifest)){
        say "\t\tcannot remove old __MANIFEST-MD5.txt";
        #not recoverable: aborting
        next;
      }
    }

    #maak nieuwe manifest
    if(!-w $scan->{path}){
      say "\t\tcannot write to directory $scan->{path}";
      #not recoverable: aborting
      next;
    }

    my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});

    local(*MANIFEST);
    open MANIFEST,">$path_manifest" or die($!);
    foreach my $file(@{ $dir_info->files() }){
      next if $file->{path} eq $path_manifest;

      say "\t\tmaking checksum for ".$file->{path};
      local(*FILE);
      if(!(
        -f -r $file->{path}
      )){
        say "\t\t$file->{path} is not a regular file or is not readable";
        unlink($path_manifest);
        #not recoverable: aborting
        next;
      }
      open FILE,$file->{path} or die($!);
      my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
      my $filename = $file->{path};
      $filename =~ s/^$old_path\///;
      print MANIFEST "$md5sum_file $filename\r\n";
      close FILE;
    }
    close MANIFEST;

    
    #verplaats  
    say "\t\tmoving from $old_path to $new_path";
    if(!move($old_path,$new_path)){
      say "\t\tcannot move $old_path to $new_path";
      #not recoverable: aborting
      next;
    }

    #pas locatie aan
    $scan->{path} = $new_path;

    #schrijf bag-info.txt uit indien het nog niet bestaat, en schrijf archive_id uit
    # door nieuwe bag-info.txt hier neer te schrijven, staat ie niet in __MANIFEST-MD5.txt!
    my($archive_id,$is_new) = sync_baginfo($scan);
    if($is_new){
      say "\t\tnew archive_id: $archive_id";
    }

    #chmod(775,$new_path) is enkel van toepassing op bestanden en mappen direct onder new_path..
    {
      my $command = "sudo chown -R $uid:$gid $new_path && sudo chmod -R $rights $new_path";
      my($stdout,$stderr,$success,$exit_code) = capture_exec($command);

      if(!$success){
        #niet zo erg, valt op te lossen via manuele tussenkomst
        say STDERR $stderr;
      }
    }

    #status 'registered'
    delete $scan->{$_} for(qw(busy));
    my $log;
    ($scan,$log) = set_status($scan,status => "registered");

    #afgeleiden maken mbv Mediamosa
    if($scan->{profile_id} eq "NARA"){

      my $command = drush_command("mmnara",$scan->{path});
      say "\t$command";
      my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
      say "stderr:";
      say $stderr;
      say "stdout:";
      say $stdout;

      if(!$success){
        say STDERR $stderr;
      }elsif($stdout =~ /new asset id: (\w+)\n/m){
        say "asset_id found:$1";
        $scan->{busy} = 1;
        $scan->{asset_id} = $1;
        $scan->{datetime_last_modified} = Time::HiRes::time;
        update_scan($scan);
      }else{
        say STDERR "cannot find asset_id in response";
      }
    }

    update_log($log,-1);
    update_scan($scan);

  }
}

say "$this_file ended at ".local_time;
