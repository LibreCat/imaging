package Imaging::Routes::home;
use Dancer ':syntax';
use Imaging qw(users);
use Catmandu::Sane;
use Catmandu::Util qw(:is);

get('/',sub{
  my $user = session('user') ? users->get( session('user')->{id} ) : undef;
  my $config = config;
  my($first_role) = @{ $user->{roles} };
  $first_role =~ s/\s//go;
  my $home_url_template = $config->{home}->{roles}->{$first_role} || $config->{home}->{default};
  my $url = sprintf($home_url_template,$user->{login});
  return redirect(uri_for($url));
});

true;
