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
use List::MoreUtils qw(first_index);

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

    #aantal directories in 01_ready
    my $mount_ready = $mount_conf->{mount}."/".$mount_conf->{subdirectories}->{ready};
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
        limit => 1,
        facet => "true",
        "facet.field" => "status"
    );
    my(%facet_counts) = @{ $result->{facets}->{facet_fields}->{status} ||= [] };
    my @states = qw(registering registered derivatives_created reprocess_metadata reprocess_derivatives reprocess_scans qa_control_ok archived archived_ok published published_ok);
    my $facet_status = {};
    foreach my $status(@states){
        $facet_status->{$status} = $facet_counts{$status} || 0;
    }
    #aantal met status:reprocess_metadata
    my $num_reprocess_metadata = $facet_status->{reprocess_metadata};

    #aantal met status:reprocess_derivatives
    my $num_reprocess_derivatives = $facet_status->{reprocess_derivatives};

    #aantal voor qa_controle
    my @states_qa_control = qw(registered derivatives_created reprocess_scans reprocess_metadata reprocess_derivatives archived);
    my $num_qa_control = 0;
    foreach my $status(@states_qa_control){
        $num_qa_control += $facet_status->{$status};
    }
    
    #aantal in publicatieproces (qa_control_ok -> published)
    my @states_publishing = qw(qa_control_ok archived archived_ok published);
    my $num_publishing = 0;
    foreach my $status(@states_publishing){
        $num_publishing += $facet_status->{$status};
    }

    #aantal in archiveringsproces (qa_control_ok -> published_ok)
    my @states_archiving = qw(qa_control_ok archived archived_ok published published_ok);
    my $num_archiving = 0;
    foreach my $status(@states_archiving){
        $num_archiving += $facet_status->{$status};
    }
    
    template('status',{
        auth => auth(),
        stats => $stats,
        num_reprocess_metadata => $num_reprocess_metadata,
        num_reprocess_derivatives => $num_reprocess_derivatives,
        num_registering => $facet_status->{registering},
        num_qa_control => $num_qa_control,
        num_publishing => $num_publishing,
        num_archiving => $num_archiving 
    });
});

true;
