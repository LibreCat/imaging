package Imaging::Routes::directory;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use Data::Pageset;
use File::Basename;

sub core {
    state $core = store("core");
}
sub directory_ready {
    state $directory_ready = core()->bag("directory_ready");
}
sub directory_reprocessing {
    state $directory_reprocessing = core()->bag("directory_reprocessing");
}
sub dbi_handle {
    state $dbi_handle = database;
}
hook before => sub {
    if(request->path =~ /^\/(ready|reprocessing)/o){
		my $auth = auth;
		my $authd = authd;
		my $subpath = $1;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}elsif(!$auth->asa('scanner')){
			request->path_info('/access_denied');
            my $params = params;
            $params->{operation} = "directory $subpath";
            $params->{action} = "view";
            $params->{referrer} = request->referer;
		}
	}
};
any('/ready',sub {
	my $config = config;
	my $params = params;
	my $directory = directory_ready->get( session('user')->{id} );
	my $user = dbi_handle->quick_select('users',{ id => session('user')->{id} });
	template('/ready',{
		directory => $directory,
		auth => auth(),
		user => $user,
		mount_conf => mount_conf()
	});
});
any('/reprocessing',sub {
    my $config = config;
    my $params = params;
	my $directory = directory_reprocessing->get( session('user')->{id} );
	my $user = dbi_handle->quick_select('users',{ id => session('user')->{id} });
    template('/reprocessing',{
        directory => $directory,
		auth => auth(),
        user => $user,
		mount_conf => mount_conf()
    });
});
any('/ready/:directory/status',sub{
	my $config = config;
    my $params = params;
	my $directory_ready = directory_ready->get( session('user')->{id} );
	my $directory;
	foreach my $dir(@{ $directory_ready->{directories} || [] }){
		if(basename($dir->{base}) eq $params->{directory}){
			$directory = $dir->{base};
			last;
		}
	}
	$directory or return not_found();
	my $user = dbi_handle->quick_select('users',{ id => session('user')->{id} });
	template('/status',{
		directory => $directory,
		auth => auth(),
        user => $user,
        mount_conf => mount_conf()
	});
});

true;
