package Imaging::Routes::status;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);

hook before => sub {
    if(request->path =~ /^\/status/o){
        if(!authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }
    }
};
any('/status',sub {

    my $params = params;
    my @users = dbi_handle->quick_select('users',{
        has_dir => 1
    },{
        order_by => 'id'
    });
    my $mount_conf = mount_conf;    
    my $stats = {};
    my $config = config;

    #aantal directories in 01_ready
    my $mount_ready = mount()."/".$mount_conf->{subdirectories}->{ready};
    foreach my $user(@users){
        my $dir_ready = $mount_ready."/".$user->{login};
        my @files = glob("$dir_ready/*");
        $stats->{ready}->{ $user->{login} } = scalar(@files);

        my $result = index_scan->search(
            query => "status:reprocess_scans AND user_login:".$user->{login},
            limit => 0
        );
        $stats->{reprocessing}->{ $user->{login} } = $result->total;
    }
    
    #status facet
    my $result = index_scan->search(
        query => "*",
        limit => 0,
        facet => "true",
        "facet.field" => "status"
    );
    my(%facet_counts) = @{ $result->{facets}->{facet_fields}->{status} ||= [] };
    my @states = @{ $config->{status}->{collection}->{status_page} || [] };
    my $facet_status = {};
    foreach my $status(@states){
        $facet_status->{$status} = $facet_counts{$status} || 0;
    }
    template('status',{
        auth => auth(),
        stats => $stats,
        facet_status => $facet_status
    });
});

true;
