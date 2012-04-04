package Imaging::Routes::users;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);

#handled by admin (first user)
#user edits its own profile!!

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
		users => \@users
	});

});
any('/users/add',sub{

	my $params = params;
	my(@errors,@messages);
	if($params->{submit}){
		my($success,$errs)=check_params_new_user();
		push @errors,@$errs;
		if(scalar(@errors)==0){
			my $user = dbi_handle->quick_select('users',{ login => $params->{login} });
			if($user){
				push @errors,"user with login $params->{login} already exists";
			}else{
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
		messages => \@messages
    });

});
any('/user/:id/delete',sub{

    my $params = params;
    my(@errors,@messages);
	my $user = dbi_handle->quick_select('users',{ id => $params->{id} });
	if(!$user){
		return forward('/not_found',{
			requested_path => request->path
		});
	}	
	if($user->{id} == 1){
		return forward("/access_denied",{
            operation => "users",
            action => "delete first user",
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
		user => $user
    });

});
any('/user/:id/edit',sub{

    my $params = params;
    my(@errors,@messages);
    my $user = dbi_handle->quick_select('users',{ id => $params->{id} });
    if(!$user){
        return forward('/not_found',{
            requested_path => request->path
        });
    }
    if($user->{id} == 1){
        return forward("/access_denied",{
            operation => "users",
            action => "edit first user",
            referrer => request->referer
        });
    }
    if($params->{submit}){
		my $roles = $params->{roles};
		if(is_string($roles)){
			$roles = [$roles];
		}elsif(!is_array_ref($roles)){
			$roles = [];
		}
		if(scalar(@$roles) == 0){
			push @errors,"one or more roles need to be supplied";
		}
		if(scalar(@errors)==0){
			dbi_handle->quick_update('users',{
				id => $params->{id}
			},{
				roles => join(', ',@$roles)
			});
			redirect(uri_for("/users"));
		}
    }

    template('user/edit',{
        errors => \@errors,
        messages => \@messages,
        user => $user
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
    if(!(
            is_string($params->{password1}) && is_string($params->{password2}) &&
            $params->{password1} eq $params->{password2}
        )
    ){
        push @errors,"passwords are not equal";
    }
	return scalar(@errors)==0,\@errors;
}

true;
