package Imaging::Routes::info;
use Dancer ':syntax';
use Imaging qw(users);
use Catmandu::Sane;

any('/info',sub{
  my $user = session('user') ? users->get( session('user')->{id} ) : undef;
  template('info',{ user => $user});
});

true;
