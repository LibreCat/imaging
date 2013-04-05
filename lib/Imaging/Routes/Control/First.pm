package Imaging::Routes::Control::First;
use Dancer ':syntax';
use Catmandu::Sane;
use Dancer::Plugin::Auth::RBAC;
use URI::Escape qw(uri_escape);

hook before => sub {

  if(request->path !~ /^\/(login|logout)/o && !authd){

    my $service = uri_escape(uri_for(request->path));
    return redirect(uri_for("/login")."?service=$service");
    
  }
};

true;
