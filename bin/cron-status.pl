#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename qw();
use File::Copy qw(copy move);
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use IO::CaptureOutput qw(capture_exec);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use File::Pid;
use URI::Escape qw(uri_escape);
use LWP::UserAgent;
use Catmandu::FedoraCommons;
use Array::Diff;
use English '-no_match_vars';
use Catmandu::MediaMosa;
use Imaging qw(:all);
use DateTime::Format::Strptime;
use DateTime;

my($pid,$pidfile);
BEGIN {

  $pidfile = "/tmp/imaging-status.pid";
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


$| = 1;

sub mediamosa {
  state $mediamosa = Catmandu::MediaMosa->new(
    %{ config->{mediamosa}->{rest_api} }
  );
}
sub complain {
  say STDERR @_;
}
sub construct_query {
  my $data = shift;
  my @parts = ();
  for my $key(keys %$data){
    if(is_array_ref($data->{$key})){
      for my $val(@{ $data->{$key} }){
        push @parts,uri_escape($key)."=".uri_escape($val);
      }
    }else{
      push @parts,uri_escape($key)."=".uri_escape($data->{$key});
    }
  }
  join("&",@parts);
}
sub mm_total_finished {
  my $asset_id = shift;

  my($total,$total_finished) = (0,0);
  my($offset,$limit,$item_count_total)=(0,200,0);

  do{
    my $vpcore = mediamosa->asset_job_list({
      user_id => "Nara",
      asset_id => $asset_id,    
      limit => $limit,
      offset => $offset
    });
    if($vpcore->header->request_result() ne "success"){
      confess $vpcore->header->request_result_description();
    }
    $item_count_total = $vpcore->header->item_count_total;
    $vpcore->items->each(sub{
      	my $job = $_[0];
     	say "\tjobid $job->{id}, status: ".$job->{status}.", job_type:".$job->{job_type};
     	$total_finished++ if $job->{status} eq "FINISHED";
     	$total++;
    });

    $offset += $limit;
  }while($offset < $item_count_total);

  return $total,$total_finished;

}
sub move_scan {
  my $scan = shift;
  my $new_path = $scan->{new_path};


  #is de operatie gezond?
  if(!(
      is_string($scan->{path}) && -d $scan->{path}
  )){

    my $p = $scan->{path} || "";
    say STDERR "Cannot move from 02_processed: scan directory '$p' does not exist";
    return;

  }elsif(!is_string($new_path)){

    say STDERR "Cannot move from $scan->{path} to '': new_path is empty";
    return;

  }elsif(! -d dirname($new_path) ){

    say STDERR "Will not move from $scan->{path} to $new_path: parent directory of $new_path does not exist";
    return;

  }elsif(-d $new_path){

    say STDERR "Will not move from $scan->{path} to $new_path: directory already exists";
    return;

  }elsif(!( 
      -w dirname($scan->{path}) &&
      -w $scan->{path})
  ){

    say STDERR "Cannot move from $scan->{path} to $new_path: system has no write permissions to $scan->{path} or its parent directory";
    return;

  }elsif(! -w dirname($new_path) ){
    
    say STDERR "Cannot move from $scan->{path} to $new_path: system has no write permissions to parent directory of $new_path";
    return;

  }


  #gebruiker bestaat?
  my $login;
  if($scan->{new_user}){
    $login = $scan->{new_user};
  }else{
    my $user = users->get( $scan->{user_id} );
    $login = $user->{login};
  }

#  my($user_name,$pass,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire)=getpwnam($login);
#  if(!is_string($uid)){
#    say STDERR "$login is not a valid system user!";
#    return;
#  }elsif($uid == 0){
#    say STDERR "root is not allowed as user";
#    return;
#  }
#  my $group_name = getgrgid($gid);
  my $user_name = $login;
  my $this_gid = getgrgid($EGID);
  my $group_name = $this_gid;

  my $old_path = $scan->{path};    
  my $manifest = "$old_path/__MANIFEST-MD5.txt";
 
  say "$old_path => $new_path";

  local(*FILE);

  #maak directory en plaats __FIXME.txt
  mkpath($new_path);
  #plaats __FIXME.txt
  open FILE,">$new_path/__FIXME.txt" or return complain($!);
  print FILE $scan->{status_history}->[-1]->{comments};
  close FILE;

 
  #verplaats bestanden die opgelijst staan in __MANIFEST-MD5.txt naar 01_ready
  #andere bestanden laat je staan (en worden dus verwijderd)
  open FILE,$manifest or return complain($!);
  while(my $line = <FILE>){
  
    $line =~ s/\r\n$/\n/;
    chomp($line);
    utf8::decode($line);
    my($checksum,$filename)=split(/\s+/o,$line);

    mkpath(File::Basename::dirname("$new_path/$filename"));   
    say "moving $old_path/$filename to $new_path/$filename";
    if(
        !move("$old_path/$filename","$new_path/$filename")
    ){
      say STDERR "could not move $old_path/$filename to $new_path/$filename";
      return;
    }
    say "moving $old_path/$filename to $new_path/$filename successfull";

  }
  close FILE; 
  
  #gelukt! verwijder nu oude map
  rmtree($old_path);
  
  #pas paden aan
  $scan->{path} = $new_path;

  #stel nieuwe gebruiker in
  #$scan->{user_id} = $scan->{new_user};

  #update databank en index
  my $log;
  ($scan,$log) = set_status($scan,status => "incoming");

  #gedaan ermee
  delete $scan->{$_} for(qw(busy new_path new_user asset_id));

  update_scan($scan);
  update_status($log,-1);

  #done? rechten aanpassen aan dat van 01_ready submap
  #775 zodat imaging achteraf de map terug in processed kan verplaatsen!
  try{
    `sudo chown -R $user_name:$group_name $scan->{path} && sudo chmod -R 775 $scan->{path}`;
  }catch{
    say STDERR $_;
  };

}


#voer niet uit wanneer imaging-register.pl draait!

my $pidfile_register = "/tmp/imaging-register.pid";
my $pid_register = File::Pid->new({
  file => $pidfile_register
});
if(-f $pid_register->file && $pid_register->running){
  die("Cannot run while registration is running\n");
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

my $scans = scans();
my $index_scan = index_scan();

#status update 1: files die verplaatst moeten worden op vraag van dashboard
{
  my $query = "status:\"reprocess_scans\" OR status:\"reprocess_scans_qa_manager\"";
  my @ids = ();

  $index_scan->searcher(

    query => $query,    
    limit => 1000

  )->each(sub{

    push @ids,$_[0]->{_id};

  });

  for my $id(@ids){
    move_scan(scans->get($id));
  }
}

#status update 2: zijn jobs van mediamosa al klaar?
{

  my $query = "status:\"registered\" AND asset_id:*";
  my @ids = ();

  $index_scan->searcher(

    query => $query,
    limit => 1000

  )->each(sub{

    push @ids,$_[0]->{_id};

  });

  for my $id(@ids){

    my $scan = $scans->get($id);
    next if !$scan->{busy};

    my $asset_id = $scan->{asset_id};

    try{
      my($total,$total_finished) = mm_total_finished($asset_id);
      if($total == $total_finished){
        delete $scan->{$_} for(qw(busy asset_id));
        update_scan($scan);
      }
      say "$id => $asset_id => total:$total, total_finished:$total_finished, so done: ".($total == $total_finished ?  "yes":"no");
    }catch{
      #job deleted by Mediamosa
      if(/The asset with ID '$asset_id' was not found in the database/){
        say "asset $asset_id was removed from Mediamosa";
        delete $scan->{$_} for(qw(busy asset_id));
        update_scan($scan);
      }
    };

  }

}

#status update 3: zitten objecten in archivering reeds in archief?
{

  #collect identifiers
  my $query = "status:\"archiving\"";
  my @ids = ();

  $index_scan->searcher(

    query => $query,
    limit => 1000

  )->each(sub{

    push @ids,$_[0]->{_id};

  });

  #check status in Fedora
  my $fedora_args = config->{fedora}->{args} // [];
  my $fedora = Catmandu::FedoraCommons->new(@$fedora_args);
  my $datetime_formatter = DateTime::Format::Strptime->new(pattern => "%FT%T.%NZ");

  for my $id(@ids){
    my $scan = scans->get($id);

    say "$id => ".$scan->{archive_id};

    my($object_profile,$object_list_datastreams,@files_grep);

    {
      my $result = $fedora->getObjectProfile(pid => $scan->{archive_id});
      if(!$result->is_ok){
        say "\terror: ".$result->error;
        next;
      }    
      $object_profile = $result->parse_content;
    }

    unless(keys %$object_profile){
      say "\terror: object profile is empty";
      next;
    }

    #my $d1 = $datetime_formatter->parse_datetime($scan->{datetime_last_modified});
    my $d1 = DateTime->from_epoch(epoch => $scan->{datetime_last_modified});
    my $d2 = $datetime_formatter->parse_datetime($object_profile->{objLastModDate});

    #state moet 'A' zijn
    say "\tobjState: ".$object_profile->{objState};
    if($object_profile->{objState} ne "A"){
      say "\terror: not archived, so skipping";
      next;
    }

    #lastModDate moet nieuwer zijn dan aanleverdatum
    say "\tdate_last_modified: $d1";
    say "\tobjLastModDate: $d2";
    my $cmp = DateTime->compare($d1,$d2);
    if($cmp > 0){
      say "\terror: local version is newer";
      next;
    }
    
    say "\tcollecting files in grep";
    #check all files are in grep
    {

      my $result = $fedora->listDatastreams(pid => $scan->{archive_id});
      say "\tgot listDatastreams";
      if(!$result->is_ok){
        say "\terror: ".$result->error;
        next;
      }         
      
      my $obj = $result->parse_content;
      @files_grep = sort map { $_->{label} } grep { $_->{dsid} =~ /^DS\.\d+$/o } @{ $obj->{datastream} };
      say "\tgrep: $_" for @files_grep;

    }

    say "\tcollecting my files";
    my @files;

    if($scan->{profile_id} eq "BAG"){
      my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path}."/data");
      @files = sort map { $_->{basename} } @{ $dir_info->files };
    }else{
      my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});
      @files = sort grep { $_ !~ /^__MANIFEST-MD5\.txt$/ && $_ ne "bag-info.txt" } map { $_->{basename} } @{ $dir_info->files };
    }
    say "my file: $_" for @files;

    my $diff = Array::Diff->diff(\@files,\@files_grep);

    if($diff->count > 0){
      say "\tnot in imaging:";
      say "\t\t$_" for(@{ $diff->added });
      say "not in grep:";
      say "\t\t$_" for(@{ $diff->deleted });
      next;
    }        

    say "\teverything ok";

    my $log;
    ($scan,$log) = set_status($scan,status => "archived");

    update_scan($scan);
    update_status($log,-1);

  }
}


say "$this_file ended at ".local_time;
