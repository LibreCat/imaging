package Imaging::Routes::Control::Last;
use Dancer ':syntax';
use Catmandu::Sane;
use Catmandu;
use Imaging qw(users :mount);
use Dancer::Plugin::Auth::RBAC;

prefix undef;

hook before_template_render => sub {
  my $tokens = $_[0];
  $tokens->{auth} = auth();
  $tokens->{authd} = authd();
  $tokens->{mount_conf} = mount_conf();
  $tokens->{mount} = mount();
  $tokens->{catmandu_conf} = Catmandu->config();
};

any('/not_found',sub{
  status 'not_found';
  header( "refresh" => config->{refresh_rate}."; URL=".uri_for(config->{default_app}) );
  template('not_found',{
    requested_path => uri_for(params->{requested_path})
  });
});
any qr{.*} => sub {
  status 'not_found';
  header( "refresh" => config->{refresh_rate}."; URL=".uri_for(config->{default_app}) );
  template('not_found',{
    requested_path => uri_for(request->path)
  });
};

true;
