#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu qw(:load);
use Dancer qw(:script);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use Imaging::Bag::Info;
use Imaging::Profile::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);
use File::Basename qw();
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Digest::MD5 qw(md5_hex);
use Time::HiRes;
use all qw(Imaging::Dir::Query::*);
use English '-no_match_vars';
use Archive::BagIt;
use File::Pid;
use IO::CaptureOutput qw(capture_exec);
use Data::UUID;
use MediaMosa;
use Imaging::Meercat qw(:all);

my $pidfile;
my $pid;
BEGIN {
   
  #voer niet uit wanneer andere instantie van imaging-register.pl draait!
  $pidfile = "/tmp/imaging-register.pid";
  $pid = File::Pid->new({
    file => $pidfile
  });
  if(-f $pid->file && $pid->running){
    die("Cannot run while registration is running\n");
  }

  #plaats lock
  say "this process id: $$";
  -f $pidfile && ($pid->remove or die("could not remove lockfile $pidfile!"));
  $pid->pid($$);
  $pid->write or die("could not place lock!");

}
END {
    #verwijder lock
    $pid->remove if $pid;
}

use Imaging qw(:all);


#variabelen
sub mount_conf {
  config->{mounts}->{directories} ||= {};
}
sub directory_translator_packages {
  state $c = do {
    my $config = config;
    my $list = [];
    if(is_array_ref($config->{directory_to_query})){
        $list = $config->{directory_to_query};
    }
    $list;
  };
}
sub directory_translator {
  state $translators = {};
  my $package = shift;
  $translators->{$package} ||= $package->new;
}
sub directory_to_queries {
  my $path = shift;
  my $packages = directory_translator_packages();    
  my @queries = ();
  foreach my $p(@$packages){
    my $trans = directory_translator($p);
    if($trans->check($path)){
      @queries = $trans->queries($path);
      last;
    }
  }
  if(scalar @queries == 0){
    push @queries,File::Basename::basename($path);
  }
  @queries;
}

sub ensure_archive_id {
  my $scan = $_[0];

  my $baginfo = {};
  $baginfo = Imaging::Bag::Info->new(source => $scan->{path}."/bag-info.txt")->hash if -f $scan->{path}."/bag-info.txt";

  if(
    is_array_ref($baginfo->{'Archive-Id'}) && scalar(@{ $baginfo->{'Archive-Id'} }) > 0
  ){

    $scan->{archive_id} = $baginfo->{'Archive-Id'}->[0];

  }else{

    $scan->{archive_id} = "archive.ugent.be:".Data::UUID->new->create_str;
    $baginfo->{'Archive-Id'} = [ $scan->{archive_id} ];
    say "new archive_id:".$scan->{archive_id};

  }

  write_to_baginfo($scan->{path}."/bag-info.txt",$baginfo);


}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;


#stap 1: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
#
#   1ste metadata-record wordt neergeschreven in bag-info.txt: mediamosa pikt deze metadata op

my @ids_ok_for_metadata = ();
{
  my $query = "-status:\"incoming\" AND -status:\"incoming_error\" AND -status:\"done\"";

  say "retrieving metadata for good scans ($query)";

  my($offset,$limit,$total) = (0,1000,0);
  do{
      my $result = index_scan->search( 
        query => $query,
        reify => scans(),
        start => $offset,
        limit => $limit
      );
      $total = $result->total;
      for my $scan(@{ $result->hits }){
        if(
            !(is_array_ref($scan->{metadata}) && scalar(@{ $scan->{metadata} }) > 0 ) &&
            !(-f $scan->{path}."/__FIXME.txt")
        ){
          push @ids_ok_for_metadata,$scan->{_id};
        }
      }
      $offset += $limit;
  }while($offset < $total);

}

foreach my $id(@ids_ok_for_metadata){
  my $scan = scans()->get($id);
  my $path = $scan->{path};
  my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});

  #parse hash indien bag-info.txt bestaat, en indien niet, maak nieuwe aan
  my $baginfo_path = $scan->{path}."/bag-info.txt";
  my $baginfo;
  if(-f $baginfo_path){
    $baginfo = Imaging::Bag::Info->new(source => $baginfo_path)->hash;
  }

  #haal metadata op
  my @queries = directory_to_queries($path);

  foreach my $query(@queries){
    my $res = meercat()->search(query => $query,source => 'source:rug01');
    $scan->{metadata} = [];
    if($res->total > 0){

      for my $hit(@{ $res->hits }){              

        push @{ $scan->{metadata} },{
          fSYS => $hit->{fSYS},#000000001
          source => $hit->{source},#rug01
          fXML => $hit->{fXML},
          baginfo => defined($baginfo) ? $baginfo : marc_to_baginfo_dc(xml => $hit->{fXML})
        };

      }
      last;
    }

  }
  my $num = scalar(@{$scan->{metadata}});
  say "\tscan ".$scan->{_id}." has $num metadata-records";

  update_scan($scan);
}
#release memory
@ids_ok_for_metadata = ();

#stap 2: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest)
my @incoming_ok = ();
{

  my($offset,$limit,$total) = (0,1000,0);
  do{
    my $result = index_scan->search(
      query => "status:\"incoming_ok\"",
      start => $offset,
      limit => $limit
    );
    $total = $result->total;
    for my $scan(@{ $result->hits }){
      if(!(-f $scan->{path}."/__FIXME.txt")){
          push @incoming_ok,$scan->{_id};
      }
    }
    $offset += $limit;
  }while($offset < $total);

}

say "registering incoming_ok";

my $mount_conf = mount_conf();
my $dir_processed = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed};

if(!-w $dir_processed){

    #not recoverable: aborting
    say "\tcannot write to $dir_processed";    

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
                set_status($scan,status => "incoming_error");
                $scan->{check_log} = \@errors;

                update_scan($scan);
                update_status($scan,-1);

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

        my $uid = data_at(config,"mounts.directories.owner.processed") || $this_uid;
        my $gid = data_at(config,"mounts.directories.group.processed") || $this_gid;
        my $rights = data_at(config,"mounts.directories.rights.processed") || "0775";

        
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
        my $new_path = "$dir_processed/".File::Basename::basename($old_path);   


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
        ensure_archive_id($scan);

        #chmod(0775,$new_path) is enkel van toepassing op bestanden en mappen direct onder new_path..
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
        set_status($scan,status => "registered");

        #afgeleiden maken mbv Mediamosa
        if($scan->{profile_id} eq "NARA"){

          my $command = sprintf(config->{mediamosa}->{drush_command}->{mmnara},$scan->{path});
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

        update_scan($scan);
        update_status($scan,-1);

    }
}
#release memory
@incoming_ok = ();

#opladen naar GREP
my @qa_control_ok = ();
{

  my($offset,$limit,$total) = (0,1000,0);
  do{
      my $result = index_scan->search(
        query => "status:\"qa_control_ok\"",
        start => $offset,
        limit => $limit
      );
      $total = $result->total;
      for my $hit(@{ $result->hits }){
          push @qa_control_ok,$hit->{_id};
      }
      $offset += $limit;
  }while($offset < $total);

}
for my $scan_id(@qa_control_ok){

    my $scan = scans->get($scan_id);

    #archive_id ? => baseer je enkel op bag-info.txt (en NOOIT op naamgeving map, ook al heet die "archive-ugent-be-lkfjs" )
    ensure_archive_id($scan);

    #naamgeving map hoeft niet conform te zijn met archive-id (enkel bag-info.txt)
    my $grep_path = config->{'archive_site'}->{mount_incoming_bag}."/".File::Basename::basename($scan->{path});
    my $is_bag = Imaging::Profile::BAG->new()->test($scan->{path});
    my $command;

    #geen bag? Maak er dan een bag van
    if(!$is_bag){

      $command = sprintf(
          config->{mediamosa}->{drush_command}->{'bt-bag'},
          $scan->{path},                   
          $grep_path
      );
        
    }else{

        $command = "cp -R $scan->{path} $grep_path && rm -f $grep_path/__MANIFEST-MD5.txt";

    }

    say "command: $command";
    my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
    say "stderr:";
    say $stderr;
    say "stdout:";
    say $stdout;

    next if !$success;

    my $uid = data_at(config,"mounts.directories.owner.archive") || "fedora";
    my $gid = data_at(config,"mounts.directories.group.archive") || "fedora";
    my $rights = data_at(config,"mounts.directories.rights.archive") || "0775";

    $command = "sudo chown -R $uid:$gid $grep_path && sudo chmod -R $rights $grep_path";
    ($stdout,$stderr,$success,$exit_code) = capture_exec($command);
    say $command;
    say "stderr:";
    say $stderr;
    say "stdout:";
    say $stdout;    
    say "scan archiving";

    set_status($scan,status => "archiving");

    update_scan($scan);
    update_status($scan,-1);

    say "scan record updated";

}
#release memory
@qa_control_ok = ();

#stap 4: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "updating list scans for projects";
my @project_ids = ();
projects()->each(sub{ 
  push @project_ids,$_[0]->{_id}; 
});

foreach my $project_id(@project_ids){

    my $project = projects()->get($project_id);

    my $query = $project->{query};
    next if !$query;

    my @list = ();

    my $meercat = meercat();

    my($offset,$limit,$total) = (0,1000,0);

    my $fetch_successfull = 1;
    try{
        do{

            my $res = $meercat->search(query => $query,fq => 'source:rug01',start => $offset,limit => $limit);
            $total = $res->total;

            foreach my $hit(@{ $res->hits }){
                my $ref = from_xml($hit->{fXML},ForceArray => 1);

                #zoek items in Z30 3, en nummering in Z30 h
                my @items = ();

                foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
                  if($marc_datafield->{tag} eq "Z30"){
                    my $item = {
                      source => $hit->{source},
                      fSYS => $hit->{fSYS}
                    };
                    foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
                      if($marc_subfield->{code} eq "3"){
                        $item->{"location"} = $marc_subfield->{content};
                      }
                      if($marc_subfield->{code} eq "h" && $marc_subfield->{content} =~ /^V\.\s+(\d+)$/o){
                        $item->{"number"} = $1;
                      }
                    }
                    say "\t".join(',',values %$item);
                    push @items,$item;
                  }
                }
                push @list,@items;
            }

            $offset += $limit;

        }while($offset < $total);

    }catch{
        $fetch_successfull = 0;
        say STDERR $_;
    };
    if($fetch_successfull){
        say "storing new object list to database";
        $project->{list} = \@list;
        $project->{datetime_last_modified} = Time::HiRes::time;
        projects()->add($project);
        project2index($project);
    }
};
{
    my($success,$error) = index_project->commit;   
    die(join('',@$error)) if !$success;
}
#release memory
@project_ids = ();


#stap 4: ken scans toe aan projects
say "assigning scans to projects";
my @scan_ids = ();
scans->each(sub{ 
    push @scan_ids,$_[0]->{_id} if !-f $_[0]->{path}."/__FIXME.txt"; 
});
while(my $scan_id = shift(@scan_ids)){
    my $scan = scans->get($scan_id);
    my $result = index_project->search(query => "list:\"".$scan->{_id}."\"");
    if($result->total > 0){        
        my @p_ids = map { $_->{_id} } @{ $result->hits };
        $scan->{project_id} = \@p_ids;
        say "assigning project $_ to scan ".$scan->{_id} foreach(@p_ids);
    }else{
        $scan->{project_id} = [];
    }    
    scans->add($scan);
    scan2index($scan);
}

{
    my($success,$error) = index_scan->commit;   
    die(join('',@$error)) if !$success;
}
#release memory
@scan_ids = ();

say "$this_file ended at ".local_time;
