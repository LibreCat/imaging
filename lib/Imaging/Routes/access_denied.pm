package Imaging::Routes::access_denied;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Catmandu::Sane;

any('/access_denied',sub{
	template('access_denied',{});
});

true;
