#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Carp qw(confess);

use Imaging::Util qw(:files :data :lock);
use Imaging::Dir::Info;
use Imaging::Scan qw(:all);

use File::Basename;
use File::Copy qw(copy move);
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use IO::CaptureOutput qw(capture_exec);
use URI::Escape qw(uri_escape);
use LWP::UserAgent;
use Catmandu::FedoraCommons;
use Array::Diff;
use English '-no_match_vars';
use Catmandu::MediaMosa;
use Imaging qw(:all);
use DateTime::Format::Strptime;
use DateTime;

my($pidfile);
INIT {

  $pidfile = "/tmp/imaging-status.pid";
  acquire_lock($pidfile);

  #voer niet uit wanneer imaging-register.pl draait!
  my $pidfile_register = "/tmp/imaging-register.pid";
  check_lock($pidfile_register);

}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}


$| = 1;

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

my $this_file = basename(__FILE__);
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
    my @errors = return_scan(scans->get($id));
    say STDERR $_ foreach @errors;
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
  my $datetime_formatter = DateTime::Format::Strptime->new(pattern => "%FT%T.%NZ");

  for my $id(@ids){
    my $scan = scans->get($id);

    say "$id => ".$scan->{archive_id};

    my($object_profile,$object_list_datastreams,@files_grep);

    {
      my $result = fedora()->getObjectProfile(pid => $scan->{archive_id});
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

      my $result = fedora()->listDatastreams(pid => $scan->{archive_id});
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

    update_log($log,-1);
    update_scan($scan);

  }
}

#status update 4: zijn er records die verwijderd mogen worden?
say "looking for scans to be purged";
{
  #collect identifiers
  my $query = "status:\"purge\"";
  my @ids = ();

  $index_scan->searcher(
    query => $query,
    limit => 1000
  )->each(sub{
    push @ids,$_[0]->{_id};
  });

  for my $id(@ids){

    my $scan = $scans->get($id);
    my $path = $scan->{path};

    #verwijder scan uit tabel 'scans', maar registreer verwijdering in tabel 'logs'
    if(is_string($path) && -d $path && !can_delete_file($path)){

      push @{ $scan->{warnings} },{
        datetime => Time::HiRes::time,
        text => "Het systeem kan deze map niet verwijderen. Contacteer uw admin om dit probleem op te lossen",
        username => "-"
      };
      $scans->add($scan);

      say "  $id: unable to delete path $path";
    
    }else{
     
      $index_scan->delete($id);
      $index_scan->commit();
      $scans->delete($id);

      if(-d $path){
        my $error;
        rmtree($path,{error => \$error});
        if(scalar(@$error)){
          say "  $id: deleted from database, but errors while deleting path $path:";
          say "    $_" for @$error;
        }else{
          say "  $id: deleted";
        }
      }else{
        say "  $id: deleted (path $path not found)";
      }

      my $log;
      ($scan,$log) = set_status($scan,status => "purged");
      update_log($log,-1);

    } 

  }
}

#status update 5: zijn er scans die opnieuw in mediamosa opgeladen moeten worden?
say "looking for scans to be reprocessed by mediamosa";
{
  #collect identifiers
  my $query = "status:\"reprocess_derivatives\"";
  my @ids = ();

  $index_scan->searcher(
    query => $query,
    limit => 1000
  )->each(sub{
    push @ids,$_[0]->{_id};
  });

  for my $id(@ids){

    my $scan = $scans->get($id);
    my $path = $scan->{path};

    my $command = drush_command("mmnara",$scan->{path});
    say "\t$command";

    next;

    my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
    say "\tstderr: $stderr" if $stderr;
    say "\tstdout: $stdout" if $stdout;

    if(!$success){

      say "\toperation failed";

    }elsif($stdout =~ /new asset id: (\w+)\n/m){

      say "\tasset_id found:$1";
      $scan->{busy} = 1;
      $scan->{asset_id} = $1;
      $scan->{datetime_last_modified} = Time::HiRes::time;

    }else{

      say "\tcannot find asset_id in response";

    }

    update_scan($scan);
    update_log(get_log($scan),-1);
  
  }

}



say "$this_file ended at ".local_time;
