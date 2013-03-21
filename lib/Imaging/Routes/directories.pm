package Imaging::Routes::directories;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use IO::CaptureOutput qw(capture_exec);

hook before => sub {
  if(request->path_info =~ /^\/directories/o && !auth->can('directories','edit')){

    request->path_info('/access_denied');
    params->{text} = "u mist de nodige rechten om de scandirectories aan te passen";

  }
};

get('/directories',sub {
  my $config = config;
  my $params = params;
  my(@errors)=();

  my $users = users->to_array;

  #sanity check on mount
  my($success,$errs) = sanity_check();
  push @errors,@$errs if !$success;

  my $mount = mount();
  my $subdirectories = subdirectories();

  foreach my $user(@$users){
    $user->{ready} = "$mount/".$subdirectories->{ready}."/".$user->{login};
  }

  #template
  template('directories',{
    users => $users,
    errors => \@errors
  });
});
post '/directories/:id' => sub {
  my $config = config;
  my $params = params;
  my(@errors,@messages);
  my $user = users->get($params->{id});
  $user or return not_found();    

  #sanity check on mount
  my($success,$errs) = sanity_check();
  push @errors,@$errs if !$success;

  my $mount = mount();
  my $subdirectories = subdirectories();

  #check directories
  $user->{ready} = "$mount/".$subdirectories->{ready}."/".$user->{login};

  if(scalar(@errors)==0){
    foreach(qw(ready)){
      try{
        my $path = "$mount/".$subdirectories->{$_}."/".$user->{login};
        mkpath($path) if(!-d $path);
        my($stdout,$stderr,$success,$exit_code) = capture_exec("chown -R $user->{login} $path && chmod -R 0755 $path");
        die($stderr) if !$success;
        push @messages,"directory '$_' is ok nu";
        users->add($user);
      }catch{
        push @errors,$_;
      };
    }
  }
  
  var errors => \@errors,
  var messages => \@messages;
  var sanity_checked => 1;

  my $id = delete $params->{id};
  forward "/directories/$id",$params,{ method => "GET" };
};
get '/directories/:id' => sub {
  my $config = config;
  my $params = params;
  my(@errors,@messages);
  my $user = users->get($params->{id});
  $user or return not_found();    

  #sanity check on mount
  if(! var('sanity_checked')){
    my($success,$errs) = sanity_check();
    push @errors,@$errs if !$success;
  }

  my $mount = mount();
  my $subdirectories = subdirectories();

  #check directories
  $user->{ready} = "$mount/".$subdirectories->{ready}."/".$user->{login};

  foreach(qw(ready)){
    if(!-d $user->{$_}){
      push @errors,"directory '$_' bestaat niet ($user->{$_})";
    }elsif(!-w $user->{$_}){
      push @errors,"systeem kan niet schrijven naar directory '$_' ($user->{$_})";
    }
  }

  my $e = var 'errors';
  my $m = var 'messages';
  push @errors,@$e if $e;
  push @messages,@$m if $m;

  template('directories/edit',{
    errors => \@errors,
    messages => \@messages,
    user => $user
  });
};

true;
