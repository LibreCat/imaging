package Imaging::Routes::users;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);
use File::Path qw(mkpath rmtree);
use Try::Tiny;

sub dbi_handle {
    state $dbi_handle = database;
}
hook before => sub {
	if(request->path =~ /^\/user/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}elsif(!$auth->can('manage_accounts','edit')){
			request->path_info('/access_denied');
			my $params = params;
			$params->{operation} = "users";
			$params->{action} = "edit";
			$params->{referrer} = request->referer;
		}
	}
};	
any('/users',sub{

	my @users = dbi_handle->quick_select('users',{},{ order_by => 'id' });
	template('users',{
		users => \@users,
		auth => auth()
	});

});
any('/users/add',sub{

	my $params = params;
	my(@errors,@messages);
	if($params->{submit}){
		my($success,$errs)=check_params_new_user();
		push @errors,@$errs;
		if(!(
     		is_string($params->{password1}) && is_string($params->{password2}) &&
            $params->{password1} eq $params->{password2}
			)
		){
			push @errors,"passwords are not equal";
		}
		if(scalar(@errors)==0){
			my $user = dbi_handle->quick_select('users',{ login => $params->{login} });
			if($user){
				push @errors,"user with login $params->{login} already exists";
			}else{
				my $roles = join('',@{ $params->{roles} });
				dbi_handle->quick_insert('users',{
					login => $params->{login},
					name => $params->{name},
					roles => join(', ',@{ $params->{roles} }),
					password => md5_hex($params->{password1})
				});
				redirect(uri_for("/users"));
			}
		}
	}
	
    template('users/add',{
        errors => \@errors,
		messages => \@messages,
		auth => auth()
    });

});
any('/user/:id/edit',sub{

    my $params = params;
    my $user = dbi_handle()->quick_select('users',{ id => $params->{id} });
	$user or return not_found();

	if($user->{login} eq "admin"){
        return forward("/access_denied",{
            operation => "users",
            action => "edit user admin",
            referrer => request->referer
        });
    }

    my(@errors,@messages);

    if($params->{submit}){
		my($success,$errs)=check_params_new_user();
        push @errors,@$errs;		
        if(scalar(@errors)==0){
			my $roles = join(', ',@{ $params->{roles} });
			my $new = {
				roles => $roles,
				login => $params->{login},
				name => $params->{name}
			};
			$user = { %$user,%$new };
            dbi_handle->quick_update('users',{ id => $params->{id} },$user);
			redirect(uri_for("/users"));
        }
    }
    template('user/edit',{ user => $user,errors => \@errors,messages => \@messages, auth => auth() });
});
any('/user/:id/delete',sub{

    my $params = params;
	my $user = dbi_handle->quick_select('users',{ id => $params->{id} });
	$user or return not_found();

    my(@errors,@messages);

	if($user->{login} eq "admin"){
		return forward("/access_denied",{
            operation => "users",
            action => "delete user admin",
            referrer => request->referer
        });
	}
    if($params->{submit}){
        dbi_handle->quick_delete('users',{
            id => $params->{id}
        });
		redirect(uri_for("/users"));
    }

    template('user/delete',{
        errors => \@errors,
        messages => \@messages,
		user => $user,
		auth => auth()
    });

});
sub check_params_new_user {
	my $params = params;
	my(@errors);
	my @keys = qw(name login);
    foreach my $key(@keys){
        if(!is_string($params->{$key})){
            push @errors,"$key must be supplied"
        }
    }
    @keys = qw(roles);
    foreach my $key(@keys){
		if(is_string($params->{$key})){
			$params->{$key} = [$params->{$key}];
		}elsif(!is_array_ref($params->{$key})){
			$params->{$key} = [];
		}
        if(!(scalar(@{ $params->{$key} }) > 0)){
            push @errors,"$key must be supplied"
        }
    }
	return scalar(@errors)==0,\@errors;
}

true;
