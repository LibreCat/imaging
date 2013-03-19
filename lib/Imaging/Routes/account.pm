package Imaging::Routes::account;
use Dancer ':syntax';
use Dancer::Plugin::Auth::RBAC;
use Imaging qw(users);
use Catmandu::Sane;
use URI::Escape qw(uri_escape);

hook before => sub {
  if(request->path_info =~ /^\/account/o){
    if(!authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};  
get('/account',sub{
  my $user = session('user') ? users->get( session('user')->{id} ) : undef;
  template('account',{ user => $user, auth => auth() });
});

true;
