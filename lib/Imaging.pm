package Imaging;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is :array);
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Time::HiRes;
use Clone qw(clone);
use Digest::MD5 qw(md5_hex);
use Imaging::Dir::Info;
use Imaging::Util qw(:files);
use XML::Simple;
use Exporter qw(import);
our @EXPORT_OK=qw(projects scans users index_scan index_log index_project meercat formatted_date local_time project2index scan2index status2index marcxml_flatten update_scan update_status set_status dir_info list_files logs get_log);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

sub projects { 
  state $projects = store()->bag("projects");
}
sub scans {
  state $scans = store()->bag("scans");
}
sub logs {
  state $logs = store()->bag("logs");
}
sub users {
  state $users = store()->bag("users");
}
sub index_scan {
  state $index_scans = store("index_scan")->bag;
}
sub index_log {
  state $index_log = store("index_log")->bag;
}
sub index_project {
  state $index_project = store("index_project")->bag;
}
sub meercat {
  state $meercat = store("meercat")->bag;
}
sub formatted_date {
  my $time = shift || Time::HiRes::time;
  DateTime::Format::Strptime::strftime(
    '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
  );
}
sub local_time {
  my $time = shift || time;
  $time = int($time);
  DateTime::Format::Strptime::strftime(
    '%FT%TZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
  );
}
sub project2doc {
  my $project = shift;
  my $doc = {};
  $doc->{$_} = $project->{$_} foreach(qw(_id name name_subproject description query num_hits));
  foreach my $key(keys %$project){
    next if $key !~ /datetime/o;
    $doc->{$key} = formatted_date($project->{$key});
  }

  my @list = ();
  foreach my $item(@{ $project->{list} || [] }){
    # id: plaatsnummer of rug01 mogelijk (verschil met name: letters verwisseld, en bijkomende nummering mogelijk bij plaatsnummers)
    if($item->{location}){
      my $id = $item->{location};
      $id =~ s/[\.\/]/-/go;
      if(defined($item->{number})){
        $id .= "-".$item->{number};
      }
      push @list,$id;
    }
    push @list,uc($item->{source})."-".$item->{fSYS};
  }
  $doc->{list} = \@list;
  # doc.list.length != project.list.size
  # doc.list => "lijst van mogelijke items"
  # project.list => "lijst van items"
  $doc->{total} = scalar(@{ $project->{list} });
 
  $doc;
}
sub project2index {
  index_project->add(project2doc($_[0]));
}
sub get_log {
  my $scan = shift;
  logs()->get($scan->{_id}) || new_log($scan);
}
sub status2docs {
  my($log,$history_index) = @_;    
  my @docs;  

  my $history_objects;
  if(array_exists($log->{status_history},$history_index)){
    $history_objects = [ $log->{status_history}->[$history_index] ];
  }else{
    $history_objects = $log->{status_history};
  }

  foreach my $history(@$history_objects){
    next if $history->{status} =~ /incoming_/o;
    my $doc = clone($history);
    $doc->{datetime} = formatted_date($doc->{datetime});
    $doc->{scan_id} = $log->{_id};
    $doc->{owner} = $log->{user_id};
    my $blob = join('',map { $doc->{$_} } sort keys %$doc);
    $doc->{_id} = md5_hex($blob);
    push @docs,$doc;    
  }

  \@docs;

}
sub status2index {
  my($log,$history_index) = @_;     
  my $index_log = index_log();
  my $docs = status2docs($log,$history_index);
  $index_log->add($_) for @$docs;
}
sub marcxml_flatten {
  my $xml = shift;
  my $ref = XML::Simple->new()->XMLin($xml,ForceArray => 1);
  my @text = ();
  foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
    foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
      next if !is_string($marc_subfield->{content});
      push @text,$marc_subfield->{content};
    }
  }
  foreach my $control_field(@{ $ref->{'marc:controlfield'} }){
    next if !is_string($control_field->{content});
    push @text,$control_field->{content};
  }
  return \@text;
}
sub scan2doc {
  my $scan = shift;      

  my $log = get_log($scan); 

  #default doc
  my $doc = clone($scan);

  #metadata
  my @metadata_ids = ();
  push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} }); 
  $doc->{metadata_id} = \@metadata_ids;
  $doc->{marc} = [];
  push @{ $doc->{marc} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});

  #status history
  for(my $i = 0;$i < scalar(@{ $log->{status_history} });$i++){
    my $item = $log->{status_history}->[$i];
    $doc->{status_history}->[$i] = $item->{user_login}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
  }

  #project info
  delete $doc->{project_id};
  if(is_array_ref($scan->{project_id}) && scalar(@{$scan->{project_id}}) > 0){
    foreach my $project_id(@{$scan->{project_id}}){
      my $project = projects->get($project_id);
      next if !is_hash_ref($project);
      foreach my $key(keys %$project){
        next if $key eq "list";
        my $subkey = "project_$key";
        $subkey =~ s/_{2,}/_/go;
        $doc->{$subkey} ||= [];
        push @{$doc->{$subkey}},$project->{$key};
      }
    }
  }

  #user info
  if($scan->{user_id}){
    my $user = users->get($scan->{user_id});
    if($user){
      my @keys = qw(name login roles);
      $doc->{"user_$_"} = $user->{$_} foreach(@keys);
    }
  }
  
  #convert datetime to iso
  foreach my $key(keys %$doc){
    next if $key !~ /datetime/o;
    if(is_array_ref($doc->{$key})){
      $_ = formatted_date($_) for(@{ $doc->{$key} });
    }else{
      $doc->{$key} = formatted_date($doc->{$key});
    }
  }

  #opkuisen
  my @deletes = qw(metadata comments busy warnings new_path new_user publication_id);
  delete $doc->{$_} for(@deletes);

  $doc;

}
sub scan2index {  
  index_scan()->add(scan2doc($_[0]));
}
sub dir_info {
  Imaging::Dir::Info->new(dir => shift);
}
sub list_files {
  my $dir = shift;
  #lijst bestanden
  my $dir_info = dir_info($dir);
  my @files = ();
  for my $file(@{ $dir_info->files() }){
    push @files,file_info($file->{path});
  }

  #sorteer bestanden
  our($a,$b);
  @files = sort {
      $a->{name} cmp $b->{name};
  } @files;

  \@files,$dir_info->size();
}

sub update_scan {
  my $scan = shift;
  scans->add($scan);
  scan2index($scan);
  my($success,$error) = index_scan->commit;
  die(join('',@$error)) if !$success;
}
sub update_status {
  my($log,$index) = @_;
  logs()->add($log);
  status2index($log,$index);
  my($success,$error) = index_log->commit;
  die(join('',@$error)) if !$success;
}
#input: <scan>,status => <new-status>,user_login => <executing user-login>,comment => <comments>
#return: scan AND log (full record!)
sub set_status {
  my($scan,%opts)=@_;

  $scan->{status} = $opts{status};
  my $log = get_log($scan);
  $log->{status_history} //= [];
  push @{ $log->{status_history} },{
    user_login => ($opts{user_login} // "-"),
    status => $opts{status},
    datetime => Time::HiRes::time,
    comments => ($opts{comments}  // "")
  };
  $scan->{datetime_last_modified} = Time::HiRes::time;
  $log->{datetime_last_modified} = $scan->{datetime_last_modified}; 

  $scan,$log;
}
sub new_log {
  my $scan = shift;
  {
    _id => $scan->{_id},
    user_id => $scan->{user_id},
    status_history => [],
    datetime_last_modified => Time::HiRes::time
  };
};

1;
