package Imaging::Routes::login;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_unescape);
use Digest::MD5 qw(md5_hex);

post('/login',sub{
  return redirect( uri_for(config->{default_app} || "/") ) if authd;
  my $params = params;
  my $auth = auth($params->{user},md5_hex($params->{password}));
  if($auth->errors){
    forward('/login',{ errors => $auth->errors },{ method => 'GET' });
  }else{
    my $service = is_string($params->{service})? uri_unescape($params->{service}) : uri_for(config->{default_app} || "/");
    return redirect( $service );
  }
});
get('/login',sub{
  return redirect( uri_for(config->{default_app} || "/") ) if authd;
  template('login',{ errors => params->{errors} || [], auth => auth() });
});
get('/logout',sub{
  if(authd){
    auth->revoke();
  }
  redirect( uri_for("/login") );
});

true;
