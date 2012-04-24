package Imaging::Routes::logs;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);

sub indexer {
    state $index = store("index_log")->bag("log_locations");
}
hook before => sub {
    if(request->path =~ /^\/logs/o){
		if(!authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};
any('/logs',sub {
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
	if($sort && $sort =~ /^\w+\s(?:asc|desc)$/o){
		$opts{sort} = [$sort,"location_id desc"];
	}else{
		$opts{sort} = ["datetime desc","location_id desc"];
	}
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
        template('logs',{
            logs => $result->hits,
            page_info => $page_info,
            auth => auth()
        });
    }else{
        template('logs',{
            logs => [],
            error => $error,
            auth => auth()
        });
    }
});

true;
