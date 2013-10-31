package Imaging::Routes::scans;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging::Meercat qw(:all);
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Email;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Try::Tiny;
use List::MoreUtils qw(first_index);
use Clone qw(clone);
use Time::HiRes;
use File::Basename qw();
use File::Path qw(mkpath rmtree);
use File::Copy qw(move);
use Data::UUID;
use Hash::Merge qw(merge);
use Imaging::Dir::Info;
use Imaging::Util qw(:files);
use Imaging::Bag::Info;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

hook before_template_render => sub {
  my $tokens = $_[0];
  $tokens->{status_change_conf} = status_change_conf();
  $tokens->{can_change_status} = \&can_change_status; 
  $tokens->{can_change_metadata} = \&can_change_metadata;
  $tokens->{archive_url} = \&archive_url;
  $tokens->{publication_url} = \&publication_url;
};
get('/scans',sub {
  my $params = params;
  my $config = config;
  my $index_scan = index_scan();

  my %opts = simple_search_params();
  $opts{sort} = $config->{app}->{scans}->{default_sort} if !defined($opts{sort}) && $config->{app}->{scans} && $config->{app}->{scans}->{default_sort};  

  my($result,@errors);
  
  try {

    my $facet_fields = config->{app}->{scans}->{facet_fields};
    if(is_array_ref($facet_fields) && scalar(@$facet_fields) > 0){
      $opts{facet} = "true";
      $opts{"facet.field"} = $facet_fields;
    }
    $result= $index_scan->search(%opts);
    
  }catch{
    push @errors,"ongeldige zoekvraag";
  };

  template('scans',{
    result => $result,
    errors => \@errors
  });
});

post '/scans/:_id/metadata' => sub {
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $auth = auth;
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  my $e = errors_change_metadata($scan);

  if(@$e){

    push @errors,@$e;
  
  }elsif(scalar(@{ $scan->{metadata} }) > 1){

    # => slecht één metadata-record mag gekoppeld zijn, dus ..
    # 1. bij toevoegen, moet 0 of 1 metadata-record moet aanwezig zijn (want wat moet je anders vervangen?). Indien meerdere, verschijnt een warning dat de slechte er eerst uit moeten
    # 2. 0 records => push, 1 record: vervang
    push @errors,"Deze scan bevat meer dan één metadata-record! Gelieve de foutieve eerst te verwijderen.";

  }else{
    
    my $metadata_id = $params->{metadata_id} || "";

    my($result,$error);
    try {

      $result = meercat->search(query => $metadata_id,limit => 1);     

    }catch{
      $error = $_;
    };
    if($error){

      push @errors,"query $metadata_id is ongeldig";

    }elsif($result->total > 1){

      push @errors,"query $metadata_id leverde meer dan één resultaat op";

    }elsif($result->total == 0){

      push @errors,"query $metadata_id leverde geen resultaten op";

    }else{

      my $doc = $result->first;
      my $baginfo = {};
      my $path_baginfo = $scan->{path}."/bag-info.txt";
      if(-f $path_baginfo){
        $baginfo = Imaging::Bag::Info->new(source => $path_baginfo)->hash;
      }
      my $dc = marc_to_baginfo_dc(xml => $doc->{fXML});
      $baginfo = { %$baginfo,%$dc };

      $scan->{metadata}->[0] = {
        fSYS => $doc->{fSYS},#000000001
        source => $doc->{source},#rug01
        fXML => $doc->{fXML},
        baginfo => $baginfo
      };

      #overschrijf archive_id
      if(is_array_ref($baginfo->{'Archive-Id'}) && scalar(@{$baginfo->{'Archive-Id'}})){
        $scan->{archive_id} = $baginfo->{'Archive-Id'}->[0];
      }
      
      #overschrijf oude bag-info.txt op de schijf
      write_to_baginfo($path_baginfo,$baginfo) if -d $scan->{path};

      push @messages,"metadata $metadata_id werd aangepast";
      
    }                    
  }

  #einde: herindexeer
  if(scalar(@errors)==0){
    scans->add($scan);
    scan2index($scan);
    index_scan->commit;
  }

  json({
    status => scalar(@errors) == 0 ? "ok":"error",
    errors => \@errors,
    messages => \@messages
  });

};

del '/scans/:_id/metadata' => sub {
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $auth = auth;
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  my $e = errors_change_metadata($scan);

  if(@$e){

    push @errors,@$e;

  }else{
    #verwijder element met metadata_id uit de lijst (mag resulteren in 0 elementen)
    my @keys = qw(metadata_id);
    foreach my $key(@keys){
      if(!is_string($params->{$key})){
        push @errors,"$key is niet opgegeven";
      }
    }
    if(scalar(@errors)==0){
      my $index = first_index { $_->{source}.":".$_->{fSYS} eq $params->{metadata_id} } @{$scan->{metadata}};
      if($index >= 0){
        splice @{$scan->{metadata}},$index,1;
        push @messages,"metadata_id $params->{metadata_id} werd verwijderd";
      }
      if(scalar(@{ $scan->{metadata} }) == 1){
        write_to_baginfo($scan->{path}."/bag-info.txt",$scan->{metadata}->[0]->{baginfo} || {}) if -d $scan->{path};
      }
    }
  }
          
  #einde: herindexeer
  if(scalar(@errors)==0){
    scans->add($scan);
    scan2index($scan);
    index_scan->commit;
  }

  json({
    status => scalar(@errors) == 0 ? "ok":"error",
    errors => \@errors,
    messages => \@messages
  });

};
get('/scans/:_id.json',sub{

  my $params = params;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  content_type 'json';

  my $response = { errors => \@errors, messages => \@messages };

  $response->{data} = $scan;  
  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  return json($response);
});

get('/scans/:_id',sub {
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;

  #projecten
  my @projects;
  if(is_array_ref($scan->{project_id})){
    foreach(@{ $scan->{project_id} }){
      my $project = projects->get($_);
      push @projects,$project if is_hash_ref($project);
    }
  }
  
  #log
  my $log = get_log($scan);

  my($files,$size);
  #lijst bestanden
  if(-d -r $scan->{path}){
    ($files,$size) = list_files($scan->{path});
  }else{
    ($files,$size) = ([],0);
  }
    
  template('scans/view',{
    scan => $scan,
    log => $log,
    files => $files,
    size => $size,
    user => users->get($scan->{user_id}),
    errors => \@errors,
    projects => \@projects
  });

});

get('/scans/:_id/comments',,sub{
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  content_type 'json';    

  my $response = { 
    status => scalar(@errors) == 0 ? "ok":"error",
    errors => \@errors,
    messages => \@messages,
    data => $scan->{comments}
  };

  return json($response);
});

post('/scans/:_id/comments',,sub{
  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();
  
  my $comment;

  content_type 'json';    

  my $response = { 
    errors => \@errors,
    messages => \@messages
  };

  my $e_blocked = errors_blocked($scan);

  if(!$auth->can('scans','comment')){

      push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";

  }elsif(scalar(@$e_blocked)){

    push @errors,@$e_blocked;

  }elsif(!is_string($params->{text})){
      
      push @errors,"parameter 'text' is leeg";

  }else{

    $comment = {
      datetime => local_time(),
      text => $params->{text},
      user_login => session('user')->{login},
      id => Data::UUID->new->create_str
    };
    push @{ $scan->{comments} ||= [] },$comment;
    scans->add($scan);

  }

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";
  $response->{data} = $comment;

  return json($response,{pretty => 0});
});
post('/scans/:_id/baginfo',sub{
  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  content_type 'json';

  my $response = { 
    errors => \@errors,
    messages => \@messages
  };

  my $e = errors_change_metadata($scan);
  push @errors,@$e if @$e;

  if(!is_string($params->{metadata_id})){
 
    push @errors,"Parameter metadata_id is niet opgegeven";

  }

  unless(@errors){
  
    my $index_metadata_id = first_index {
      my $id = $_->{source}.":".$_->{fSYS};
      $id eq $params->{metadata_id};
    }  @{ $scan->{metadata} };

    if($index_metadata_id < 0){

      push @errors,"metadata_id $params->{metadata_id} niet gevonden in record";

    }else{

      my $baginfo_params = clone($params);
      delete $baginfo_params->{$_} foreach(qw(_id metadata_id));

      my($baginfo,$errs) = validate_baginfo($baginfo_params);
      push @errors,@$errs if !$baginfo;

      if(scalar(@errors)==0){

        my $old_baginfo = $scan->{metadata}->[$index_metadata_id]->{baginfo};
        my $baginfo_restricted_keys = baginfo_restricted_keys();

        #kopiëer restricted keys
        my $restricted = {};
        foreach(@$baginfo_restricted_keys){
          $restricted->{$_} = $old_baginfo->{$_};
        }
        $baginfo = { %$baginfo,%$restricted };
        
        $scan->{metadata}->[$index_metadata_id]->{baginfo} = $baginfo;

        if(scalar(@{ $scan->{metadata} }) == 1){
          write_to_baginfo($scan->{path}."/bag-info.txt",$scan->{metadata}->[0]->{baginfo} || {}) if -d $scan->{path};
        }

        push @messages,"baginfo werd aangepast";
        scans->add($scan);

      }
    }

  }

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  return json($response);
});

get '/status_change' => sub {
  my $auth = auth;
  my $params =  params();
  if(!$auth->can('scans','status')){

    return forward('/access_denied',{
      text => "U mist de nodige gebruikersrechten om de status van dit record aan te passen"
    });

  }
  my @scans;
  for my $id(@{ $params->{_id} || [] }){
    my $scan = scans()->get($id);
    next unless $scan;
    push @scans,$scan;
  }
  my $results = var 'results';
  template 'status_change',{ results => $results,scans => \@scans };
};
post '/status_change' => sub {
  my $auth = auth;
  my $params = params();
  if(!$auth->can('scans','status')){

    return forward('/access_denied',{
      text => "U mist de nodige gebruikersrechten om de status van dit record aan te passen"
    });

  }

  my @results;

  var 'results' => \@results;

  forward '/status_change',$params,{ method => "GET" };
};

post '/scans/:_id/status' => sub {
  my $params = params;
  my $auth = auth;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  content_type 'json';

  my $response = {
    errors => \@errors,
    messages => \@messages
  };

  my $res = change_status($scan,%$params,commit => 1);
  push @errors,@{ $res->{errors} };
  push @messages,@{ $res->{messages} };    

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  json($response);

};

sub conf_baginfo {
  state $conf_baginfo = config->{app}->{scans}->{edit}->{baginfo};
}
sub baginfo_restricted_keys {
  state $keys = do{
    my @keys = ();
    my $conf = conf_baginfo();
    foreach(@$conf){
      push @keys,$_->{key} unless $_->{edit};
    }
    \@keys;
  };
}
sub validate_baginfo_pair {
  my($key,$value) = @_;
  my @errors = ();
  my $conf_baginfo = conf_baginfo();
  
  if(!is_string($key)){

    push @errors,"sleutel van baginfo is leeg";

  }elsif(!is_string($value)){

    push @errors,"waarde van baginfo sleutel $key is leeg";

  }else{

    my $index_baginfo_key = first_index {
      $_->{key} eq $key;
    } @$conf_baginfo;
    if($index_baginfo_key < 0){

      push @errors,"$key is een ongeldige baginfo sleutel";

    }elsif( 
      !$conf_baginfo->[$index_baginfo_key]->{edit} 
    ){

      push @errors,"$key kan niet worden aangepast";

    }else{
      my $conf_baginfo_key = $conf_baginfo->[$index_baginfo_key];
      my $values = $conf_baginfo_key->{'values'};
      if(
        is_array_ref($values) && !array_includes($values,$value)
      ){
        push @errors,"'$value' is niet toegelaten als waarde voor $key";
      }
    }

  }

  scalar(@errors) == 0,\@errors;
}
sub validate_baginfo {
  my($baginfo) = @_;
  my @errors = ();
  my $good_baginfo = {};

  foreach my $key(keys %$baginfo){
    my $values = is_array_ref($baginfo->{$key}) ? $baginfo->{$key} : [ $baginfo->{$key} ];
    foreach my $value(@$values){
      my($success,$errs) = validate_baginfo_pair($key,$value);
      if($success){
        $good_baginfo->{$key} ||= [];
        push @{ $good_baginfo->{$key} },$value;
      }else{
        push @errors,@$errs;
      }
    }
  }
  #required?
  for(@{ conf_baginfo() }){
    if($_->{required} && !exists($baginfo->{$_->{key}})){
      push @errors,"$_->{key} werd niet opgegeven (verplicht)";
    }
  }
  scalar(@errors) == 0 ? $good_baginfo:undef,\@errors;
}
sub ensure_path {
  my $path = shift;

  if(! (-d $path)){
    mkpath($path);
  }
  if(! (-f "$path/__MANIFEST-MD5.txt")){
    open my $fh,">:utf8","$path/__MANIFEST-MD5.txt" or die($!);
    close $fh;
  }
}
sub errors_blocked {
  my $scan = $_[0]; 
  my @errors;

  if($scan->{busy}){

    push @errors,"Systeem is bezig met een operatie op deze scan";

  }elsif(-f $scan->{path}."/__FIXME.txt"){

    push @errors,"Dit record moet gerepareerd worden. Voer de noodzakelijke bewerkingen uit, en verwijder daarna __FIXME.txt uit de map";

  }

  \@errors;
}
sub status_change_conf {
  my $session = session();
  my $config = config();
  my $merge = {};
  for(@{ $session->{user}->{roles} }){
    $merge = merge($merge,$config->{status}->{change}->{$_} || {});
  }
  $merge;
}
sub status_change_allowed {
  my($from,$to) = @_;
  my $status_to_allowed = status_change_conf()->{$from}->{'values'} || [];
  array_includes($status_to_allowed,$to)
}
sub can_change_metadata_when {
  state $edit_when = config->{app}->{scans}->{edit}->{'when'} // [];
  array_includes($edit_when,$_[0]);
}
sub errors_change_metadata {
  my $scan = $_[0];
  my $auth = auth;
  my @errors;

  my $e_blocked = errors_blocked($scan);

  if(!(
      $auth->asa("admin") || $auth->can("scans","metadata")
  )){

    push @errors,"U mist de nodige gebruikersrechten om dit record te kunnen aanpassen";

  }elsif(scalar(@$e_blocked)){

    push @errors,@$e_blocked;

  }elsif(!can_change_metadata_when($scan->{status})){

    push @errors,"Metadata kan in deze status niet worden aangepast";

  }

  \@errors;
}
sub can_change_metadata {
  my $scan = $_[0];
  scalar(@{ errors_change_metadata($scan) }) == 0;
}
#geef aan of er geen enkele status wijziging mogelijk is
sub can_change_status {
  my $scan = $_[0];
  scalar @{errors_change_status($scan)} == 0;
}
#geef redenen waarom geen enkele status wijziging niet mogelijk is
sub errors_change_status {
  my $scan = $_[0];
  my $auth = auth();
  my @errors;

  my $e_blocked = errors_blocked($scan);

  if(! ($auth->can('scans','status') || $auth->asa("admin")) ){

    push @errors,"U mist de nodige gebruikersrechten om de status van dit record aan te passen";

  }elsif(scalar(@$e_blocked)){

    push @errors,@$e_blocked;

  }

  \@errors;
}
sub change_status {
  my($scan,%opts) = @_;

  my @errors;
  my @messages;

  my $e = errors_change_status($scan);

  if(@$e){
    push @errors,@$e;
  }

  unless(@errors){

    my $status_from = $scan->{status};
    my $status_to = $opts{status_to};
    my $comments = $opts{comments} // "";        
    my $mount_conf = mount_conf();

    if(!is_string($status_to)){

      push @errors,"Gelieve de nieuwe status op te geven";

    }elsif(!is_string($comments)){

      push @errors,"Gelieve een reden op te geven voor deze status wijziging";

    }else{

      if(status_change_allowed($status_from,$status_to)){

        #wijzig status
        my $log;
        ($scan,$log) = set_status($scan,
          status => $status_to,
          user_login => session('user')->{login},
          comments => $comments
        );
        #neem op in comments
        my $text = "wijzing status $status_from naar $status_to";
        $text .= ":$comments" if $comments;
        push @{ $scan->{comments} ||= [] },{
          datetime => local_time(),
          text => $text,
          user_login => session('user')->{login},
          id => Data::UUID->new->create_str
        };
        $scan->{datetime_last_modified} = Time::HiRes::time;


        if($status_to eq "reprocess_metadata"){

          my $message = template("mail_catalography",{
            scan => $scan,
            session => session(),
            comments => $comments,
            "link" => uri_for("/scans/".$scan->{_id})."#tab-metadata"
          },{ 
            layout=>undef
          });
          

          my $status = email { message => $message };
          if(defined($status->{type}) && $status->{type} eq "failure"){
              
            push @errors,"Mail naar catalografie kon niet worden verzonden:".$status->{string};

          }else{

            push @messages,"Een mail werd verzonden naar de catalografie!";

          }

        }
        #reprocess_scans: verplaats naar 01_ready van owner + __FIXME.txt
        elsif($status_to eq "reprocess_scans"){

          ensure_path($scan->{path});

          $scan->{busy} = 1;
          my $user = users->get($scan->{user_id});
          $scan->{new_path} = mount()."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login}."/".$scan->{_id};

        }
        #reprocess_scans_qa_manager: verplaats naar eigen 01_ready + __FIXME.txt
        elsif($status_to eq "reprocess_scans_qa_manager"){

          ensure_path($scan->{path});

          $scan->{busy} = 1;
          $scan->{new_path} = mount()."/".$mount_conf->{subdirectories}->{ready}."/".session('user')->{login}."/".$scan->{_id};
          #cron-to-incoming laten weten dat scan wordt toegewezen aan andere gebruiker..
          $scan->{new_user} = session('user')->{login};

        }
        #registered: terug verplaatsen van processed naar registered
        elsif($status_to eq "registered"){
          my $new_path = mount()."/".$mount_conf->{subdirectories}->{registered}."/".$scan->{_id};
          if(-d $scan->{path} && $scan->{path} ne $new_path){
            move($scan->{path},$new_path);
            $scan->{path} = $new_path;
          }
        }
        #scan is bekeken door qa_manager? Hij kan dus verplaatst worden naar 03_processed
        else{
          my $new_path = mount()."/".$mount_conf->{subdirectories}->{processed}."/".$scan->{_id};
          if(-d $scan->{path} && $scan->{path} ne $new_path){
            move($scan->{path},$new_path);
            $scan->{path} = $new_path;
          }
        }

        scans->add($scan);
        scan2index($scan);
        logs()->add($log);
        log2index($log,-1);

        if($opts{commit}){
          change_status_commit();
        }

      }else{

        push @errors,"status kan niet worden gewijzigd van $status_from naar $status_to";

      }
    }
  }

  { errors => \@errors, messages => \@messages };

}
sub change_status_commit {
  index_scan->commit;
  index_log->commit;
}
sub archive_url {
  my $scan = $_[0];
  my $url;
  if($scan->{archive_id}){
    $url = Catmandu->config->{archive_site}->{base_url}."/app/search?func=view&amp;_id=".$scan->{archive_id};
  }
  $url;
}
sub publication_url {
  my $scan = $_[0];
  my $url;
  if($scan->{archive_id} && $scan->{status} =~ /^(?:published|published_ok|done)$/){
    $url = Catmandu->config->{publication_site}->{base_url}."/view/".$scan->{archive_id};
  }
  $url;
}

1;
