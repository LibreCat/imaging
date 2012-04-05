package Imaging::Routes::directories;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use Data::Pageset;
use URI::Escape qw(uri_escape);

sub dbi_handle {
    state $dbi_handle = database;
}

hook before => sub {
    if(request->path =~ /^\/directories/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}elsif(!$auth->can('directories','edit')){
			request->path_info('/access_denied');
            my $params = params;
            $params->{operation} = "directories";
            $params->{action} = "edit";
            $params->{referrer} = request->referer;
		}
	}
};
any('/directories',sub {
	my $config = config;
	my $params = params;
	my(@errors)=();

	my @users = dbi_handle->quick_select('users',{},{ order_by => 'id' });

	my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;

    my $page_info = Data::Pageset->new({
        'total_entries'       => scalar(@users),
        'entries_per_page'    => $num,
        'current_page'        => $page,
        'pages_per_set'       => 8,
        'mode'                => 'fixed'
    });
	#sanity check on mount
	my($success,$errs) = sanity_check();
	push @errors,@$errs if !$success;
	@users = splice(@users,$offset,$num);
	#template
    template('directories',{
        users => \@users,
		errors => \@errors,
		page_info => $page_info,
		auth => auth()
    });
});
any('/directories/:id/edit',sub {
    my $config = config;
    my $params = params;
	my(@errors,@messages);
    my $user = dbi_handle->quick_select('users',{ id => $params->{id} });
	$user or return not_found();	
	if($user->{roles} !~ /scanner/o){
		return forward("/access_denied",{
            operation => "users",
            action => "create directory for user with other than 'scanner'",
            referrer => request->referer
        });
	}

	#sanity check on mount
    my($success,$errs) = sanity_check();
    push @errors,@$errs if !$success;

	my $mount = mount();
    my $subdirectories = subdirectories();

	if($params->{submit} && scalar(@errors)==0){
		foreach(qw(ready reprocessing)){
			try{
				my $path = "$mount/".$subdirectories->{$_}."/".$user->{login};
				mkpath($path);
				$user->{$_} = $path;
				dbi_handle->quick_update("users",{ id => $user->{id} },$user);
                push @messages,"directory '$_' is ok now";
			}catch{
				push @errors,$_;
			};
		}
	}else{
		foreach(qw(ready reprocessing)){
			if(!$user->{$_}){
				my $path = "$mount/".$subdirectories->{$_}."/".$user->{login};
				if(!-d $path){
					push @errors,"directory '$_' does not exist ($path)";
				}elsif(!-w $path){
					push @errors,"directory '$_' is not writable ($path)";
				}else{
					$user->{$_} = $path;
					dbi_handle->quick_update("users",{ id => $user->{id} },$user);
					push @messages,"directory '$_' is ok now";
				}
			}elsif(!-d $user->{$_}){
				push @errors,"directory '$_' does not exist ($user->{$_})";
			}elsif(!-w $user->{$_}){
				push @errors,"directory '$_' does not exist ($user->{$_})";
			}else{
				push @messages,"directory '$_' is ok";
			}
		}
	}

	template('directories/edit',{
		errors => \@errors,
		messages => \@messages,
		user => $user,
		auth => auth()
	});
});

true;
