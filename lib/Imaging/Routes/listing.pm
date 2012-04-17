package Imaging::Routes::listing;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Try::Tiny;
use File::Find;

sub dbi_handle {
    state $dbi_handle = database;
}
sub core {
    state $core = store("core");
}
sub locations {
    state $locations = core()->bag("locations");
}
hook before => sub {
	if(request->path =~ /^\/ready/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};	
any('/ready/:user_login',sub{
	my $params = params;
	my $user = dbi_handle->quick_select('users',{ login => $params->{user_login} });
    $user or return not_found();
    if(!(auth->asa('admin') || $user->{id} eq session('user')->{id})){
        return forward('/access_denied',{ 
			text => "no access to directory ready of user $params->{user_login}"
		});
    }
	
	my $mount = mount();
    my $subdirectories = subdirectories();
    my $dir = "$mount/".$subdirectories->{ready}."/".$user->{login};
	
	my @directories = ();
    if(-d $dir){
        local(*DIR);
        opendir DIR,$dir;
        while(my $file = readdir(DIR)){

            next if $file eq "." || $file eq "..";
			my $path = "$dir/$file";
			next if !-d $path;
            my $obj = {
                name => $file,
				record => locations()->get($file)
            };
            push @directories,$obj;
        }
        closedir(DIR);
		template('ready',{
			directories => \@directories,
			mount_conf => mount_conf(),
			user => $user
		});
    }
});
any('/ready/:user_login/:location_id',sub{
    my $params = params;
    my $user = dbi_handle->quick_select('users',{ login => $params->{user_login} });
    $user or return not_found();
    if(!(auth->asa('admin') || $user->{id} eq session('user')->{id})){
        return forward('/access_denied',{
            text => "no access to directory ready of user $params->{user_login}"
        });
    }

	my $location = locations()->get($params->{location_id});
	$location or return not_found();

	my $mount = mount();
    my $subdirectories = subdirectories();
	my @errors = ();

	#fout: BHSL-PAP-000 in zowel 01_ready/geert als 01_ready/jan: enkel de 1ste werd opgenomen!
	if($location->{user_id} != $user->{id}){
		push @errors,"$location->{_id} eerst bij gebruiker $user->{login} aangetroffen.";
		push @errors,"De gegevens hieronder weerspiegelen dus zijn/haar map. Verwijder uw map of overleg.";
		push @errors,"Uw map: $mount/".$subdirectories->{ready}."/".$location->{_id};
	}
	
	template('ready/view',{
		location => $location,
		errors => \@errors
	});
});

true;
