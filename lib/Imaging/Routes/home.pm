package Imaging::Routes::info;
use Dancer ':syntax';
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Imaging::Routes::Utils;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);

hook before => sub {
  if(request->path =~ /^\/$/o){
    my $auth = auth;
    my $authd = authd;
    if(!$authd){
      my $service = uri_escape(uri_for(request->path));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};  
get('/',sub{
  my $user = dbi_handle()->quick_select('users',{ id => session('user')->{id} });
  my $config = config;
  my($first_role) = split (',',$user->{roles});
  $first_role =~ s/\s//go;
  my $home_url_template = $config->{home}->{roles}->{$first_role} || $config->{home}->{default};
  my $url = sprintf($home_url_template,$user->{login});
  return redirect(uri_for($url));
});

true;
