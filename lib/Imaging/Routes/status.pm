package Imaging::Routes::status;
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
use List::MoreUtils qw(first_index);

sub core {
    state $core = store("core");
}
sub indexer {
    state $index = store("index")->bag("locations");
}
sub locations {
    state $locations = core()->bag("locations");
}
sub dbi_handle {
    state $dbi_handle = database;
}

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
        roles => { like => '%scanner%'  }
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

		my $result = indexer->search(
			query => "status:reprocess_scans AND user_login:".$user->{login},
			limit => 0
		);
		$stats->{reprocessing}->{ $user->{login} } = $result->total;
	}
	
	#aantal met status:reprocess_metadata
	my $result = indexer->search(
		query => "status:reprocess_metadata",
		limit => 0
	);	
	my $num_reprocess_metadata = $result->total;

	#aantal met status:reprocess_derivatives
    $result = indexer->search(
        query => "status:reprocess_derivatives",
        limit => 0
    );
    my $num_reprocess_derivatives = $result->total;

	#aantal voor qa_controle
	my @states_qa_control = qw(registered derivatives_created reprocess_scans reprocess_metadata reprocess_derivatives archived);
    my $q_qa_control = join(' OR ',map {
        "status:$_"
    } @states_qa_control);
	$result = indexer->search(
        query => $q_qa_control,
        limit => 0
    );  
    my $num_qa_control = $result->total;
	
	#aantal in publicatieproces (qa_control_ok -> published)
    my @states_publishing = qw(qa_control_ok published);
    my $q_publishing = join(' OR ',map {
        "status:$_"
    } @states_publishing);
    $result = indexer->search(
        query => $q_publishing,
        limit => 0
    );
    my $num_publishing = $result->total;

	#aantal in archiveringsproces (qa_control_ok -> published_ok)
	my @states_archiving = qw(qa_control_ok published published_ok);
    my $q_archiving = join(' OR ',map {
        "status:$_"
    } @states_archiving);
	$result = indexer->search(
        query => $q_archiving,
        limit => 0
    );
    my $num_archiving = $result->total;
	
	template('status',{
		auth => auth(),
		stats => $stats,
		num_reprocess_metadata => $num_reprocess_metadata,
		num_reprocess_derivatives => $num_reprocess_derivatives,
		num_qa_control => $num_qa_control,
		num_publishing => $num_publishing,
		num_archiving => $num_archiving	
	});
});

true;
