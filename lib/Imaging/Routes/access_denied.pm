package Imaging::Routes::access_denied;
use Dancer ':syntax';
use Catmandu::Sane;

get('/access_denied',sub{
  my $params = params();
  template('access_denied',$params);
});

true;
