package Imaging::Route;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Catmandu::Sane;

prefix undef;

any('/not_found',sub{
    status 'not_found';
    header( "refresh" => config->{refresh_rate}."; ".uri_for(config->{default_app}) );
    template('not_found',{
        requested_path => uri_for(params->{requested_path})
    });
});
any qr{.*} => sub {
    status 'not_found';
    header( "refresh" => config->{refresh_rate}."; ".uri_for(config->{default_app}) );
    template('not_found',{
        requested_path => uri_for(request->path)
    });
};

true;
