package Imaging::Routes::account;
use Dancer ':syntax';
use Imaging qw(users);
use Catmandu::Sane;

get('/account',sub{
  my $user = session('user') ? users->get( session('user')->{id} ) : undef;
  template('account',{ user => $user });
});

true;
