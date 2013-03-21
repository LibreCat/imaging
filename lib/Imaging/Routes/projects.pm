package Imaging::Routes::projects;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use URI::Escape qw(uri_escape);
use DateTime::Format::Strptime;
use Time::HiRes;
use Try::Tiny;
use Digest::MD5 qw(md5_hex);

hook before => sub {
  if(request->path_info =~ /^\/project(.*)$/o){
    my $auth = auth;
    my $authd = authd;
    my $subpath = $1;
    if(!$authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }elsif($subpath =~ /(?:add|delete)/o && !$auth->can('projects','edit')){
      request->path_info('/access_denied');
      my $params = params;
      $params->{text} = "U beschikt niet over de nodige rechten om projectinformatie aan te passen"
    }
  }
};
get('/projects',sub {
  
  my $config = config;
  my $params = params;
 
  my $q = $params->{q} || "*";
  my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
  $params->{page} = $page;
  my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
  $params->{num} = $num;
  my $offset = ($page - 1)*$num;
  
  my %opts = (query => $q,offset => $offset,limit => $num); 
  if(is_string($params->{'sort'}) && $params->{'sort'} =~ /^(\w+)\s(asc|desc)$/o){
    $opts{sort} = $params->{sort};
  }

  my $result = index_project->search(%opts);

  my $page_info = Data::Pageset->new({
    'total_entries'       => $result->total,
    'entries_per_page'    => $num,
    'current_page'        => $page,
    'pages_per_set'       => 8,
    'mode'                => 'fixed'
  });
  template('projects',{
    page_info => $page_info,
    projects => $result->hits
  }); 

});
get('/projects/add',sub{
  my $config = config;
  my $params = params;    
  my(@messages,@errors);

  my $e = var 'errors';
  push @errors,@$e if $e;
  my $m = var 'messages';
  push @messages,@$m if $m;

  template('projects/add',{
    errors => \@errors,
    messages => \@messages
  });
});
post('/projects/add',sub{
  my $config = config;
  my $params = params;    
  my(@messages,@errors);

  #check empty string
  my @keys = qw(name name_subproject description datetime_start query);
  foreach my $key(@keys){
    if(!is_string($params->{$key})){
      push @errors,"$key is niet opgegeven";
    }
  }
  #check empty array
  @keys = qw();
  foreach my $key(@keys){
    if(is_string($params->{$key})){
      $params->{$key} = [$params->{$key}];
    }elsif(!is_array_ref($params->{$key})){
      $params->{$key} = [];
    }
    if(scalar( @{ $params->{$key} } ) == 0){
      push @errors,"$key is niet opgegegeven (een of meerdere)";
    }
  }
  #check format
  my %check = (
    datetime_start => sub{
      my $value = shift;
      my($success,$error)=(1,undef);
      try{
        DateTime::Format::Strptime::strptime("%d-%m-%Y",$value);
      }catch{
        $success = 0;
        $error = "invalid start date (day-month-year)";
      };  
      return $success,$error;
    }
  );  
  if(scalar(@errors)==0){
    foreach my $key(keys %check){
      my($success,$error) = $check{$key}->($params->{$key});
      push @errors,$error if !$success;
    }
  }

  #check query
  my($m_result,$m_error);
  try {
    $m_result = meercat->search(query => $params->{query},fq => 'source:rug01',limit => 0);
  }catch{
    $m_error = $_;
  };
  if($m_error){
    push @errors,"query $params->{query} is een ongeldige query";
  }elsif($m_result->total <= 0){
    push @errors,"query $params->{query} leverde geen resultaten op";
  }
  #insert
  if(scalar(@errors)==0){
    #bestaat reeds?
    my $_id = md5_hex($params->{name}.$params->{name_subproject});
    my $other_project = projects->get($_id);
    if($other_project){
      push @errors,"Er bestaat reeds een project met naam '$params->{name}' en subproject '$params->{name_subproject}'";
    }else{

      $params->{datetime_start} =~ /^(\d{2})-(\d{2})-(\d{4})$/o;
      my $datetime = DateTime->new( day => int($1), month => int($2), year => int($3));
      my $project = projects->add({
        _id => $_id,
        name => $params->{name},
        name_subproject => $params->{name_subproject},
        description => $params->{description},
        datetime_start => $datetime->epoch,
        datetime_last_modified => Time::HiRes::time,
        query => $params->{query},
        num_hits => $m_result->total,
        list => []
      });
      project2index($project);
      index_project->commit;
      return redirect(uri_for("/projects"));

    }
  }

  var errors => \@errors;
  var messages => \@messages;

  forward '/projects/add',$params,{ method => "GET" };

});
get('/project/:_id',sub{
  my $config = config;
  my $params = params;
  my $auth = auth;
  my(@messages,@errors);

  #check project existence
  my $project = projects->get($params->{_id});
  if(!$project){
    return forward('/not_found',{
      requested_path => request->path_info
    });
  }
  
  my $e = var 'errors';
  push @errors,@$e if $e;
  my $m = var 'messages';
  push @messages,@$m if $m;

  template('project/view',{
    errors => \@errors,
    messages => \@messages,
    project => $project
  });
});
post('/project/:_id',sub{
  my $config = config;
  my $params = params;
  my $auth = auth;
  my(@messages,@errors);

  #check project existence
  my $project = projects->get($params->{_id});
  if(!$project){
    return forward('/not_found',{
      requested_path => request->path_info
    });
  }

  #check rights
  if(!$auth->can("projects","edit")){

    push @errors,"U beschikt niet over de nodige rechten om projectinformatie aan te passen";       

  }else{
    #check empty string
    my @keys = qw(name name_subproject description datetime_start query);
    foreach my $key(@keys){
      if(!is_string($params->{$key})){
        push @errors,"$key is niet opgegeven";
      }
    }
    #check empty array
    @keys = qw();
    foreach my $key(@keys){
      if(is_string($params->{$key})){
        $params->{$key} = [$params->{$key}];
      }elsif(!is_array_ref($params->{$key})){
        $params->{$key} = [];
      }
      if(scalar( @{ $params->{$key} } ) == 0){
        push @errors,"$key is niet opgegeven (een of meerdere)";
      }
    }
    #check format
    my %check = (
      datetime_start => sub{
        my $value = shift;
        my($success,$error)=(1,undef);
        try{
          my $datetime = DateTime::Format::Strptime::strptime("%d-%m-%Y",$value);          
        }catch{
          $success = 0;
          $error = "startdatum is ongeldig (dag-maand-jaar)";
        };
        return $success,$error;
      }
    );
    if(scalar(@errors)==0){
      foreach my $key(keys %check){
        my($success,$error) = $check{$key}->($params->{$key});
        push @errors,$error if !$success;
      }
    }
    #insert => pas op: wijzig _id niet!!!! (bij /add wordt _id afgeleid door md5_hex(name+name_subproject))
    if(scalar(@errors)==0){
      $params->{datetime_start} =~ /^(\d{2})-(\d{2})-(\d{4})$/o;
      my $datetime = DateTime->new( day => int($1), month => int($2), year => int($3));
      my $new = {
        name => $params->{name},
        name_subproject => $params->{name_subproject},
        description => $params->{description},
        datetime_start => $datetime->epoch,
        datetime_last_modified => Time::HiRes::time,
        query => $params->{query}
      };
      $project = { %$project,%$new };
      projects->add($project);
      project2index($project);
      index_project->commit;
      return redirect(uri_for("/projects"));
    }
  }

  var errors => \@errors;
  var messages => \@messages;

  my $_id = delete $params->{_id};

  forward "/project/$_id",$params,{ method => "GET" };

});
get('/project/:_id/delete',sub{

  my $config = config;
  my $params = params;
  my(@messages,@errors);

  #check project exists
  my $project = projects->get($params->{_id});
  if(!$project){
    return forward('/not_found',{
      requested_path => request->path_info
    });
  }

  template('project/delete',{
    errors => \@errors,
    messages => \@messages,
    project => $project
  });

});

post('/project/:_id/delete',sub{

  my $config = config;
  my $params = params;
  my(@messages,@errors);

  #check project exists
  my $project = projects->get($params->{_id});
  if(!$project){
    return forward('/not_found',{
      requested_path => request->path_info
    });
  }

  #remove and back to list
  projects->delete($params->{_id});
  index_project->delete($params->{_id});
  index_project->commit;
  return redirect(uri_for("/projects"));  

});

true;
