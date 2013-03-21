package Imaging::Routes::access_denied;
use Dancer ':syntax';
use Catmandu::Sane;

get('/access_denied',sub{
  template('access_denied');
});

true;
