package Imaging::Routes::users;
use Dancer  ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util  qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);
use Try::Tiny;

hook before => sub {
  if(request->path =~ /^\/user/o){
    my $auth = auth;
    my $authd = authd;
    if(!$authd){
      my $service = uri_escape(uri_for(request->path));
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

  my @users = dbi_handle->quick_select('users',{},{   order_by    =>  'id'    });
  template('users',{
    users => \@users
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
    my $user = dbi_handle->quick_select('users',{ login => $params->{login} });
    if($user){
        push @errors,"er bestaat reeds een gebruiker met als login $params->{login}";
    }else{
      my $roles = join('',@{$params->{roles}});
      try{
        dbi_handle->quick_insert('users',{
          login   =>  $params->{login},
          name    =>  $params->{name},
          roles   =>  join(', ',@{$params->{roles}}),
          password  =>  md5_hex($params->{password1})
        });
        redirect(uri_for("/users"));
      }catch{
        say STDERR $_;
        push @errors,"er bestaat reeds een gebruiker met als login $params->{name}";       
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
  my $user = dbi_handle()->quick_select('users',{    id  =>  $params->{id}   });
  $user or return  not_found();

  if($user->{login} eq "admin"){
    return forward("/access_denied",{
      text =>  "user has not the right to edit user information"
    });
  }

  my(@errors,@messages);

  my($success,$errs)=check_params_new_user();
  push @errors,@$errs;     
  if(scalar(@errors)==0){
    my $roles = join(', ',@{$params->{roles}});
    my $new = {
      roles   =>  $roles,
      #wijzig login niet!
      #login   =>  $params->{login},
      name    =>  $params->{name}
    };
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
          $new->{password} = md5_hex($params->{password1});
      }
    }
    if(scalar(@errors)==0){
      $user = { %$user,%$new };
      try{
          dbi_handle->quick_update('users',{id => $params->{id}},$user);
          redirect(uri_for("/users"));
      }catch{
          say STDERR $_;
          push @errors,"Uw verzoek kon niet worden uitgevoerd. Mogelijks bestaat de naam of login reeds al";        
      }
    }
  }

  var errors => \@errors;
  var messages => \@messages;

  my $id = delete $params->{id};
  
  forward "/user/$id/edit",$params,{ method => "GET" };

};
get('/user/:id/edit',sub{

  my $params = params;
  my $user = dbi_handle()->quick_select('users',{    id  =>  $params->{id}   });
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
  my $user = dbi_handle->quick_select('users',{id => $params->{id}});
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
    try{
      dbi_handle->quick_delete('users',{
          id  =>  $params->{id}
      });
      redirect(uri_for("/users"));
    }catch{
      say STDERR $_;
      push @errors,"Record kon niet worden verwijderd door een systeemfout. Contacteer de administrator voor meer gegevens.";
    }
  }

  var errors => \@errors;
  var messages => \@messages;
  
  my $id = delete $params->{id};
  forward "/user/$id/delete",$params,{ method => "GET" };

};
get('/user/:id/delete',sub{

  my $params = params;
  my $user = dbi_handle->quick_select('users',{id => $params->{id}});
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
