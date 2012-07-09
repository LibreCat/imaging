package Imaging::Routes::static;
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
any('/static/:id',sub{
    return params->{id};
});

true;
