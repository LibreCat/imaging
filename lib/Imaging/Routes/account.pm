package Imaging::Routes::account;
use Dancer ':syntax';
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Imaging::Routes::Utils;
use Catmandu::Sane;
use URI::Escape qw(uri_escape);

hook before => sub {
  if(request->path =~ /^\/account/o){
    if(!authd){
      my $service = uri_escape(uri_for(request->path));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};  
get('/account',sub{
  my $user = dbi_handle()->quick_select('users',{ id => session('user')->{id} });
  template('account',{ user => $user, auth => auth() });
});

true;
