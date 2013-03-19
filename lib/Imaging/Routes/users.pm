package Imaging::Routes::users;
use Dancer  ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util  qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);
use Try::Tiny;

hook before => sub {
  if(request->path_info =~ /^\/user/o){
    my $auth = auth;
    my $authd = authd;
    if(!$authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }elsif(!$auth->can('manage_accounts','edit')){
      request->path_info('/access_denied');
      my $params = params;
      $params->{text} = "U beschikt niet over de nodige rechten om gebruikersinformatie aan te passen";
    }
  }
};  
hook before_template_render => sub {
  my $tokens = $_[0];
  $tokens->{auth} = auth();
};
get('/users',sub{

  template('users',{
    users => users->to_array
  });

});
post '/users/add' => sub {
  my $params = params;
  my(@errors,@messages);

  my($success,$errs)=check_params_new_user();
  push @errors,@$errs;
  if(!(
      is_string($params->{password1}) && is_string($params->{password2}) &&
      $params->{password1} eq  $params->{password2}
    )
  ){
    push @errors,"paswoorden komen niet met elkaar overeen";
  }
  if(scalar(@errors)==0){
    my $user = users->get( $params->{login} );
    if($user){
        push @errors,"er bestaat reeds een gebruiker met als login $params->{login}";
    }else{
      try{
        users->add({
          _id => $params->{login},
          login =>  $params->{login},
          name =>  $params->{name},
          roles =>  $params->{roles},
          password => md5_hex($params->{password1})
        });
        redirect(uri_for("/users"));
      }catch{        
        push @errors,"er bestaat reeds een gebruiker met als login $params->{login}";       
      };
    }
  }
  

  var 'errors' => \@errors;
  var 'messages' => \@messages;

  forward '/users/add',$params,{ method => "GET" };

};
get('/users/add',sub{

  my $params = params;
  my(@errors,@messages);

  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;
  
  template('users/add',{
    errors => \@errors,
    messages => \@messages
  });

});
post '/user/:id/edit' => sub {
  my $params = params;
  my $user = users->get($params->{id});
  $user or return not_found();

  if($user->{login} eq "admin"){
    return forward("/access_denied",{
      text =>  "user has not the right to edit user information"
    });
  }

  my(@errors,@messages);

  my($success,$errs)=check_params_new_user();
  push @errors,@$errs;     
  if(scalar(@errors)==0){
    #wijzig 'login' en '_id' niet!

    $user->{roles} = $params->{roles};
    $user->{name} = $params->{name};

    #nieuw  wachtwoord  opgegeven?  ->  check!
    if($params->{edit_passwords}){
      if(!(
          is_string($params->{password1}) &&  
          is_string($params->{password2}) &&
          $params->{password1}    eq  $params->{password2}
          )
      ){
        push  @errors,"paswoorden komen niet met elkaar overeen";
      }else{
        $user->{password} = md5_hex($params->{password1});
      }
    }
    if(scalar(@errors)==0){            
      users->add($user);
      redirect(uri_for("/users"));
    }
  }

  var errors => \@errors;
  var messages => \@messages;

  my $id = delete $params->{id};
  
  forward "/user/$id/edit",$params,{ method => "GET" };

};
get('/user/:id/edit',sub{

  my $params = params;
  my $user = users->get($params->{id});
  $user or return  not_found();

  if($user->{login} eq "admin"){
    return  forward("/access_denied",{
      text =>  "user has not the right to edit user information"
    });
  }

  my(@errors,@messages);

  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;

  template('user/edit',{  
    user => $user,
    errors => \@errors,
    messages => \@messages
  });

});
post '/user/:id/delete' => sub {
  my $params = params;
  my $user = users->get($params->{id});
  $user or return not_found();

  if($user->{login} eq "admin"){
    return forward("/access_denied",{
        text =>  "gebruiker beschikt niet over de nodige rechten om gebruikersgegevens aan te passen"
    });
  }

  my(@errors,@messages);

  if(user_has_scans($params->{id})){

    push @errors,"Een of meerdere actieve scans zijn nog gekoppeld aan deze gebruiker. Verwijder de scans eerst.";

  }else{
    users->delete($params->{id});
    redirect(uri_for("/users"));
  }

  var errors => \@errors;
  var messages => \@messages;
  
  my $id = delete $params->{id};
  forward "/user/$id/delete",$params,{ method => "GET" };

};
get('/user/:id/delete',sub{

  my $params = params;
  my $user = users->get($params->{id});
  $user or return not_found();

  if($user->{login} eq "admin"){
    return forward("/access_denied",{
      text =>  "gebruiker beschikt niet over de nodige rechten om gebruikersgegevens aan te passen"
    });
  }

  my(@errors,@messages);
  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;

  template('user/delete',{
    errors => \@errors,
    messages => \@messages,
    user => $user
  });

});
sub check_params_new_user {
  my $params = params;
  my(@errors);
  my @keys  = qw(name login);
  foreach my $key(@keys){
    if(!is_string($params->{$key})){
        push @errors,"$key is niet opgegeven"
    }
  }
  @keys = qw(roles);
  foreach my $key(@keys){
    if(is_string($params->{$key})){
      $params->{$key} =   [$params->{$key}];
    }elsif(!is_array_ref($params->{$key})){
      $params->{$key} =   [];
    }
    if(!(scalar(@{$params->{$key}}) > 0)){
      push @errors,"$key is niet opgegeven"
    }
  }
  @keys = qw(login);
  foreach my $key(@keys){
    if($params->{$key} !~ /^\w+$/o){
      push @errors,"$key moet alfanumeriek zijn";
    }
  }
  my($name,$pass,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwnam($params->{login});
  if(!defined($uid)){
    push @errors,"user '$params->{login}' bestaat niet in het systeem";
  }elsif($uid == 0){
    push @errors,"root wordt niet toegelaten als gebruiker";
  }   
  return scalar(@errors)==0,\@errors;
}
sub user_has_scans {
  my $user_id = shift;
  my $result = index_scan->search(query => "user_id:\"$user_id\" AND -status:published_ok",limit => 0);
  $result->total > 0;
}

true;
