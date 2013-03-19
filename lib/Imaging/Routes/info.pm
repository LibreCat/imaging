package Imaging::Routes::info;
use Dancer ':syntax';
use Dancer::Plugin::Auth::RBAC;
use Imaging qw(users);
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);

hook before => sub {
  if(request->path_info =~ /^\/$/o){
    my $auth = auth;
    my $authd = authd;
    if(!$authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};  
any('/info',sub{
  my $user = session('user') ? users->get( session('user')->{id} ) : undef;
  template('info',{ user => $user, auth => auth() });
});

true;
