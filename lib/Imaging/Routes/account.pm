package Imaging::Routes::account;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);

#handled by user
#user edits its own profile!!

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
	template('account',{ user => $user });
});
any('/account/edit',sub{
    my $user = dbi_handle()->quick_select('users',{ id => session('user')->{id} });
	my $params = params;
	my(@errors,@messages);
	if($params->{submit}){
		my @keys = qw(old_password new_password);
		foreach my $key(@keys){
			if(!is_string($params->{$key})){
				push @errors,"$key is not supplied";
			}
		}
		if(scalar(@errors)==0){
			if(md5_hex($params->{old_password}) ne $user->{password}){
				push @errors,"old password is not correct";
			}else{
				my $new_password = md5_hex($params->{new_password});
				dbi_handle->quick_update('users',{ id => session('user')->{id} },{ password => $new_password });
				$user->{new_password} = $new_password;
				session('user')->{password} = $new_password;
				push @messages,"password was updated successfully";
			}
		}
	}
    template('account/edit',{ user => $user,errors => \@errors,messages => \@messages });
});

true;
