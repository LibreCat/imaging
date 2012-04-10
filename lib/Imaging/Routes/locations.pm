package Imaging::Routes::locations;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);

sub core {
    state $core = store("core");
}
sub indexer {
    state $index = store("index")->bag("locations");
}
sub locations {
    state $locations = core()->bag("locations");
}
sub projects {
    state $projects = core()->bag("projects");
}
sub dbi_handle {
    state $dbi_handle = database;
}
hook before => sub {
    if(request->path =~ /^\/locations/o){
		if(!authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};
any('/locations',sub {
	my $params = params;
    my $indexer = indexer();
    my $q = is_string($params->{q}) ? $params->{q} : "*";

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;
    my $sort = $params->{sort};

    my %opts = (
        query => $q,
        start => $offset,
        limit => $num
    );
    $opts{sort} = $sort if $sort && $sort =~ /^\w+\s(?:asc|desc)$/o;
    my($result,$error);
    try {
        $result= indexer->search(%opts);
    }catch{
        $error = $_;
    };
    if(!$error){
        my $page_info = Data::Pageset->new({
            'total_entries'       => $result->total,
            'entries_per_page'    => $num,
            'current_page'        => $page,
            'pages_per_set'       => 8,
            'mode'                => 'fixed'
        });
        template('locations',{
            locations => $result->hits,
            page_info => $page_info,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }else{
        template('locations',{
            locations => [],
            error => $error,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});
any('/locations/view',sub {
    my $params = params;
    my $indexer = indexer();
    $params->{q} = is_string($params->{q}) ? $params->{q} : "*";
    $params->{start} = is_natural($params->{start}) && int($params->{start}) >= 0 ? int($params->{start}) : 0;
    my %opts = (
        query => $params->{q},
        reify => locations(),
        start => $params->{start},
        limit => 1
    );

    my $page = session('page');
    my $num = session('num');
    $page = is_natural($page) && int($page) > 0 ? int($page) : 1;
    $num = is_natural($num) && int($num) > 0 ? int($num): 20;
    session('page' => $page);
    session('num' => $num);

    my($result,$error);
    try {
        $result = indexer->search(%opts);
    }catch{
        $error = $_;
    };
    if(!$error){
        my $project;
        if($result->hits->[0]->{project_id}){
            $project = projects->get($result->hits->[0]->{project_id});
        }
        template('locations/view',{
            location => $result->hits->[0],
            auth => auth(),
            error => $error,
            mount_conf => mount_conf(),
            project => $project,
            user => dbi_handle->quick_select('users',{ id => $result->hits->[0]->{user_id} })
        });
    }else{
        template('locations/view',{
            location => [],
            error => $error,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});
any('/locations/view/:_id',sub {
    my $params = params;
    my $_id = delete $params->{_id};
    $params->{q} = "_id:\"$_id\"";
    redirect(uri_for('/locations/view',$params));
});

true;
