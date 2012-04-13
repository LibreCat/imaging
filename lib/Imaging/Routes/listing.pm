package Imaging::Routes::listing;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Try::Tiny;
use File::Find;

sub dbi_handle {
    state $dbi_handle = database;
}
hook before => sub {
	if(request->path =~ /^\/(?:ready|processed|reprocessing)/o){
		my $auth = auth;
		my $authd = authd;
		if(!$authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};	
any('/ready/*/**',sub{
	my($user_login,$parts) = splat;
	list("ready",$user_login,$parts);
});
any('/ready/*',sub{
	my($path)=splat;
	my $params = params;
	my $newpath = '/ready/'.$path.'/.';
	forward($newpath,$params);
});
any('/ready/:user_login/',sub{
    my $params = params;
    my $newpath = '/ready/'.$params->{user_login}.'/.';
	delete $params->{user_login};
    forward($newpath,$params);
});
any('/reprocessing/*/**',sub{
    my($user_login,$parts) = splat;
    list("reprocessing",$user_login,$parts);
});
any('/reprocessing/*',sub{
    my($path)=splat;
    my $params = params;
    my $newpath = '/reprocessing/'.$path.'/.';
    forward($newpath,$params);
});
any('/reprocessing/:user_login/',sub{
    my $params = params;
    my $newpath = '/reprocessing/'.$params->{user_login}.'/.';
    delete $params->{user_login};
    forward($newpath,$params);
});

sub list {
	my($type,$user_login,$parts) = @_;
	my $user = dbi_handle->quick_select('users',{ login => $user_login });
    $user or return not_found();
    if(!(auth->asa('admin') || $user->{id} eq session('user')->{id})){
        return forward('/access_denied',{ operation => "directory $type of user $user_login", action => "list" });
    }
    my $mount = mount();
    my $subdirectories = subdirectories();
    my $subdir = "$mount/".$subdirectories->{$type}."/".$user->{login};

    my $subpath = join('/',@$parts);
    my $path = "$subdir/$subpath";

    my @files = ();
    if(-d $path){
        local(*DIR);
        if(scalar(@$parts) > 1 || $parts->[0] !~ /^.$/o){
            push @files,{
                name => "..",
                is_dir => 1,
                href => "/$type/$user_login/$subpath/.."
            };
        }
        opendir DIR,$path;
        while(my $file = readdir(DIR)){
            next if $file eq "." || $file eq "..";
            my $obj = {
                name => $file
            };
            if(-d $path."/$file"){
                $obj->{href} = "/$type/$user_login/$subpath/$file";
                $obj->{is_dir} = 1;
            }
            push @files,$obj;
        }
        closedir(DIR);
    }
    template('directory/view',{
        dir => "/$type/$user_login/$subpath",
        files => \@files
    });
}

true;
