package Imaging::Routes::scans;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging::Meercat qw(:all);
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Email;
use Catmandu::Sane;
use Catmandu;
use Catmandu::Util qw(:is :array);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);
use Clone qw(clone);
use Time::HiRes;
use File::Basename qw();
use File::Path qw(mkpath);
use Data::UUID;
use Hash::Merge qw(merge);

use Imaging::Dir::Info;
use Imaging::Util qw(:files);
use Imaging::Bag::Info;

Hash::Merge::specify_behavior({
  "SCALAR" => {
    "SCALAR" => sub { $_[1] },
    "ARRAY"  => sub { [ $_[0], @{$_[1]} ] },
    "HASH"   => sub { $_[1] },
  },
  "ARRAY" => {
    "SCALAR" => sub { $_[1] },
    "ARRAY"  => sub { [ @{$_[0]}, @{$_[1]} ] },
    "HASH"   => sub { $_[1] },
  },
  "HASH" => {
    'SCALAR' => sub { $_[1] },
    'ARRAY'  => sub { [ values %{$_[0]}, @{$_[1]} ] },
    'HASH'   => sub { Hash::Merge::_merge_hashes( $_[0], $_[1] ) },
  }
});

hook before => sub {
  if(request->path_info =~ /^\/scans/o){
    if(!authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};
hook before_template_render => sub {
  my $tokens = $_[0];
  $tokens->{status_change_conf} = status_change_conf();
};
get('/scans',sub {
  my $params = params;
  my $config = config;
  my $index_scan = index_scan();
  my $q = is_string($params->{q}) ? $params->{q} : "*";

  my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
  $params->{page} = $page;
  my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
  $params->{num} = $num;
  my $offset = ($page - 1)*$num;
  my $sort = $params->{sort};

  my %opts = (
    query => $q,
    start => $offset,
    limit => $num
  );

  if($sort =~ /^\w+\s(?:asc|desc)$/o){
    $opts{sort} = $sort;
  }else{
    $opts{sort} = $config->{app}->{scans}->{default_sort} if $config->{app}->{scans} && $config->{app}->{scans}->{default_sort};
  }

  my @errors = ();
  my($result);
  my $facets = [];
  try {
    my $facet_fields = config->{app}->{scans}->{facet_fields};
    if(is_array_ref($facet_fields) && scalar(@$facet_fields) > 0){
      $opts{facet} = "true";
      $opts{"facet.field"} = $facet_fields;
    }
    $result= $index_scan->search(%opts);
    $facets = $result->{facets};
  }catch{
    push @errors,"ongeldige zoekvraag";
  };
  if(scalar(@errors)==0){
    my $page_info = Data::Pageset->new({
      'total_entries'       => $result->total,
      'entries_per_page'    => $num,
      'current_page'        => $page,
      'pages_per_set'       => 8,
      'mode'                => 'fixed'
    });
    return template('scans',{
      scans => $result->hits,
      facets => $facets,
      page_info => $page_info
    });
  }else{
    return template('scans',{
      scans => [],
      errors => \@errors
    });
  }
});

post '/scans/:_id' => sub {
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $auth = auth;
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  #bewerk metadata
  if(is_string($params->{action})){
    if(!(
        $auth->asa("admin") || $auth->can("scans","metadata")
    )){

      return forward('/access_denied',{
          text => "U mist de nodige gebruikersrechten om dit record te kunnen aanpassen"
      });

    }elsif($scan->{busy}){

      push @errors,"Systeem is bezig met een operatie op deze scan";

    }elsif(-f $scan->{path}."/__FIXME.txt"){

      push @errors,"Dit record moet gerepareerd worden. Voer de noodzakelijke bewerkingen uit, en verwijder daarna __FIXME.txt uit de map";

    }else{
      # => slecht één metadata-record mag gekoppeld zijn, dus ..
      # 1. bij toevoegen, moet 0 of 1 metadata-record moet aanwezig zijn (want wat moet je anders vervangen?). Indien meerdere, verschijnt een warning dat de slechte er eerst uit moeten
      # 2. 0 records => push, 1 record: vervang                
   
      if($params->{action} eq "add_metadata"){

        if(scalar(@{ $scan->{metadata} }) > 1){

          push @errors,"Deze scan bevat meer dan één metadata-record! Gelieve de foutieve eerst te verwijderen.";

        }else{
      
          my $metadata_id = $params->{metadata_id} || "";

          my($result,$error);
          try {

            $result = meercat->search(query => $metadata_id,limit => 1,fq => 'source:rug01');     

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
            
            #overschrijf oude bag-info.txt op de schijf
            write_to_baginfo($path_baginfo,$baginfo) if -f $path_baginfo;

            push @messages,"metadata $metadata_id werd aangepast";

          }
        }                    
      }
      #verwijder element met metadata_id uit de lijst (mag resulteren in 0 elementen)
      elsif($params->{action} eq "delete_metadata"){

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
            write_to_baginfo($scan->{path}."/bag-info.txt",$scan->{metadata}->[0]->{baginfo} || {}) if -f $scan->{path}."/bag-info.txt";
          }
        }

      }else{

        push @errors,"actie '$params->{action}' is ongeldig";

      }

      #einde: herindexeer
      if(scalar(@errors)==0){
        scans->add($scan);
        scan2index($scan);
        index_scan->commit;
      }
    }
  }

  var errors => \@errors;
  var messages => \@messages;

  delete $params->{_id};
  forward "/scans/".$scan->{_id},$params,{ method => "GET" };

};
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

  my($files,$size);
  #lijst bestanden
  if(-d -r $scan->{path}){
    ($files,$size) = list_files($scan->{path});
  }else{
    ($files,$size) = ([],0);
  }
    
  template('scans/view',{
    scan => $scan,
    files => $files,
    size => $size,
    user => users->get($scan->{user_id}),
    errors => \@errors,
    projects => \@projects
  });

});
get('/scans/:_id/json',sub{

  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});

  content_type 'json';

  my $response = { };

  if(!$scan){
      push @errors, "scandirectory $params->{_id} niet gevonden";
  }else{
      $response->{data} = $scan;
  }
  $response->{status} = scalar(@errors) == 0 ? "ok":"error";
  $response->{errors} = \@errors;
  $response->{messages} = \@messages;
  return to_json($response,{pretty => 0});

});

get('/scans/:_id/comments',,sub{
  my $params = params;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});

  my $comments = [];
  
  content_type 'json';    

  my $response = { };

  if(!$scan){

    push @errors, "scandirectory $params->{_id} niet gevonden";

  }else{
    
    $comments = $scan->{comments};
            
  }

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";
  $response->{errors} = \@errors;
  $response->{messages} = \@messages;
  $response->{data} = $comments;

  return to_json($response,{pretty => 0});
});

post('/scans/:_id/comments',,sub{
  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  
  my $comment;

  content_type 'json';    

  my $response = { };

  if(!$scan){

      push @errors, "scandirectory $params->{_id} niet gevonden";

  }elsif(!$auth->can('scans','comment')){

      push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";

  }elsif($scan->{busy}){

      push @errors,"Systeem is bezig met een operatie op deze scan";

  }elsif(-f $scan->{path}."/__FIXME.txt"){

      push @errors,"Dit record moet gerepareerd worden. Voer de noodzakelijke bewerkingen uit, en verwijder daarna __FIXME.txt uit de map";

  }
  elsif(!is_string($params->{text})){
      
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
  $response->{errors} = \@errors;
  $response->{messages} = \@messages;
  $response->{data} = $comment;

  return to_json($response,{pretty => 0});
});
post('/scans/:_id/baginfo',sub{
  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});

  content_type 'json';

  my $response = { };

  if(!$scan){

    push @errors, "scandirectory $params->{_id} niet gevonden";

  }elsif(!($auth->asa('admin') || $auth->can('scans','metadata'))){
      
    push @errors,"U mist de juiste rechten om de baginfo aan te passen";

  }elsif($scan->{busy}){

    push @errors,"Systeem is bezig met een operatie op deze scan";

  }elsif(-f $scan->{path}."/__FIXME.txt"){

    push @errors,"Dit record moet gerepareerd worden. Voer de noodzakelijke bewerkingen uit, en verwijder daarna __FIXME.txt uit de map";

  }elsif(!is_string($params->{metadata_id})){

    push @errors,"Parameter metadata_id is niet opgegeven";

  }else{

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
          write_to_baginfo($scan->{path}."/bag-info.txt",$scan->{metadata}->[0]->{baginfo} || {}) if -f $scan->{path}."/bag-info.txt";
        }

        push @messages,"baginfo werd aangepast";
        scans->add($scan);

      }
    }
  }

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";
  $response->{errors} = \@errors;
  $response->{messages} = \@messages;
  return to_json($response,{pretty => 0});
});

post '/scans/:_id/:status' => sub {
  my $params = params;
  my $auth = auth;
  my $config = config;
  my @errors = ();
  my @messages = ();
  my $mount_conf = mount_conf;
  my $session = session();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  if(! $auth->can('scans','status') ){
    return forward('/access_denied',{
        text => "U mist de nodige gebruikersrechten om de status van dit record aan te passen"
    });
  }
  my $status_change_conf = status_change_conf();

  if($scan->{busy}){

    push @errors,"Systeem is bezig met een operatie op deze scan";

  }elsif(-f $scan->{path}."/__FIXME.txt"){

    push @errors,"Dit record moet gerepareerd worden. Voer de noodzakelijke bewerkingen uit, en verwijder daarna __FIXME.txt uit de map";

  }else{

    my $comments = $params->{comments} // "";        
    my $status_from = $scan->{status};
    my $status_to = $params->{status_to};

    if(!is_string($status_to)){

      push @errors,"Gelieve de nieuwe status op te geven";

    }elsif(!is_string($comments)){

      push @errors,"Gelieve een reden op te geven voor deze status wijziging";

    }else{

      if(status_change_allowed($status_from,$status_to)){

        #wijzig status
        $scan->{status} = $status_to;
        #voeg toe aan status history    
        push @{ $scan->{status_history} ||= [] },{
          user_login => session('user')->{login},
          status => $status_to,
          datetime => Time::HiRes::time,
          comments => $comments
        };
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

        scans->add($scan);
        scan2index($scan);
        status2index($scan,-1);
        my($success,$error) = index_scan->commit;
        ($success,$error) = index_log->commit;

        #redirect
        return redirect(uri_for("/scans/$scan->{_id}"));
      }else{

        push @errors,"status kan niet worden gewijzigd van $status_from naar $status_to";

      }
    }
  }

  var errors => \@errors;
  var messages => \@messages;

  delete $params->{_id};  
  forward("/scans/".$scan->{_id}."/status",$params,{ method => "GET" });

};

get('/scans/:_id/status',sub{
  my $params = params();
  my @errors = ();
  my @messages = ();
  my $scan = scans->get($params->{_id});
  $scan or return not_found();

  if(! auth()->can('scans','status') ){
    return forward('/access_denied',{
      text => "U mist de nodige gebruikersrechten om de status van dit record aan te passen"
    });
  }

  #indien men hierheen is geforwarded via post route
  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;

  template('scans/status',{
    scan => $scan,
    errors => \@errors,
    messages => \@messages,
    user => users->get($scan->{user_id})
  });

});
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
sub fedora {
  state $fedora = Catmandu::FedoraCommons->new(@{ config->{fedora}->{args} // [] });
}

true;
