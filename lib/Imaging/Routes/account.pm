package Imaging::Routes::account;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);

sub dbi_handle {
    state $dbi_handle = database;
}
hook before => sub {
	if(request->path =~ /^\/account/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};	
any('/account',sub{
	my $user = dbi_handle()->quick_select('users',{ id => session('user')->{id} });
	template('account',{ user => $user, auth => auth() });
});

true;
