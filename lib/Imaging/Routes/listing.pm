package Imaging::Routes::listing;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use URI::Escape qw(uri_escape);
use Try::Tiny;
use File::Find;

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

            my $dir_info = dir_info($path);
            my $obj = {
                name => $file,
                info => $dir_info,
                record => scans()->get($file)
            };
            push @directories,$obj;
        }
        closedir(DIR);
        template('ready',{
            directories => \@directories,
            mount_conf => mount_conf(),
            user => $user,
            auth => auth()
        });
    }
});
any('/ready/:user_login/:scan_id',sub{
    my $params = params;
    my $mount_conf = mount_conf();

    #user bestaat
    my $user = dbi_handle->quick_select('users',{ login => $params->{user_login} });
    $user or return not_found();

    #directory bestaat
    my $scan_id = $params->{scan_id};
    my $path = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login}."/$scan_id";
    -d $path or return not_found();

    my @errors = ();

    #controleer op conflict
    my $has_conflict = 0;
    my $scan = scans()->get($scan_id);
    my($files,$size) = list_files($path);
    if($scan && $scan->{path} ne $path){
        $has_conflict = 1;
        my $other_user = dbi_handle->quick_select('users',{ id => $scan->{user_id} });
        push @errors,"$scan->{_id} werd eerst bij gebruiker $other_user->{login} aangetroffen.Deze map zal daarom niet verwerkt worden.";
    }

    template('ready/view',{
        scan_id => $scan_id,
        scan => $scan,
        has_conflict => $has_conflict,
        path => $path,
        files => $files,
        size => $size,
        user => $user,
        errors => \@errors,
        auth => auth()
    });
});

true;
