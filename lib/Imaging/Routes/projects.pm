package Imaging::Routes::projects;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use URI::Escape qw(uri_escape);

sub core {
    state $core = store("core");
}
sub projects {
	state $projects = core()->bag("projects");
}
hook before => sub {
    if(request->path =~ /^\/project/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}elsif(!$auth->can('projects','edit')){
			request->path_info('/access_denied');
            my $params = params;
            $params->{operation} = "projects";
            $params->{action} = "edit";
            $params->{referrer} = request->referer;
		}
	}
};

any('/projects',sub {
	
	my $config = config;
	my $params = params;

	my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
	$params->{page} = $page;
	my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
	$params->{num} = $num;
	my $offset = ($page - 1)*$num;

	my $projects = projects->slice($offset,$num)->to_array();
	my $page_info = Data::Pageset->new({
        'total_entries'       => projects->count,
        'entries_per_page'    => $num,
        'current_page'        => $page,
        'pages_per_set'       => 8,
        'mode'                => 'fixed'
    });
	template('projects',{
		page_info => $page_info,
		projects => $projects
	});	
});
any('/projects/add',sub{
	my $config = config;
	my $params = params;	
	my(@messages,@errors);
	my $success = 0;

	#check empty
	my @keys = qw(code name description);
	foreach my $key(@keys){
		if(!is_string($params->{$key})){
			push @errors,"$key must be supplied";
		}
	}	
	#check code
	if(scalar(@errors)==0){
		my $project = projects->get($params->{code});
		if($project){
			push @errors,"project with code $params->{code} already exists";
		}else{
			projects->add({
				_id => $params->{code},	
				name => $params->{name},
				description => $params->{description}
			});
			push @messages,"project $params->{code} was added to the list!";
			$success = 1;
		}
	}

	template('projects/add',{
		errors => \@errors,
		messages => \@messages,
		success => $success
	});
});
any('/project/:code/delete',sub{
    my $config = config;
    my $params = params;
    my(@messages,@errors);
    my $success = 0;
	my $project;

    #check project exists
    if(!is_string($params->{code})){
		push @errors,"code must be supplied";
    }else{
		$project = projects->get($params->{code});
		if(!$project){
			push @errors,"$params->{code} does not exist";
		}
	}
	#delete?
	if(scalar(@errors) == 0 && $params->{submit}){
		projects->delete($params->{code});
		push @messages,"project $params->{code} was deleted successfully";
		$success = 1;
	}

    template('project/delete',{
        errors => \@errors,
        messages => \@messages,
        success => $success,
		project => $project
    });
});

true;
