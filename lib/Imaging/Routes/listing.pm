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
    if(!(auth->asa('admin') || $user->{id} eq session('user')->{id})){
        return forward('/access_denied',{ 
            text => "U mist de nodige rechten om de scandirectory van $params->{user_login} te bekijken"
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
    my $user = dbi_handle->quick_select('users',{ login => $params->{user_login} });
    $user or return not_found();
    if(!(auth->asa('admin') || $user->{id} eq session('user')->{id})){
        return forward('/access_denied',{
            text => "no access to directory ready of user $params->{user_login}"
        });
    }


    my $scan = scans()->get($params->{scan_id});
    $scan or return not_found();

    my $status = $scan->{status};
    if($status eq "registering"){
        
        forward('/access_denied',{
            text => "Het systeem is bezig met het registreren van deze map. Hij zal binnenkort verplaatst worden naar 02_processed, en zal de status 'registered' krijgen"
        });

    }

    my @errors = ();
    my $mount = mount();
    my $subdirectories = subdirectories();

    #fout: BHSL-PAP-000 in zowel 01_ready/geert als 01_ready/jan: enkel de 1ste werd opgenomen!
    if($scan->{user_id} != $user->{id}){
        my $other_user = dbi_handle->quick_select('users',{ id => $scan->{user_id} });
        push @errors,"$scan->{_id} eerst bij gebruiker $other_user->{login} aangetroffen.";
        push @errors,"De gegevens hieronder weerspiegelen dus zijn/haar map. Verwijder uw map of overleg.";
        push @errors,"Uw map: $mount/".$subdirectories->{ready}."/".$user->{login}."/".$scan->{_id};

    }
    
    template('ready/view',{
        scan => $scan,
        errors => \@errors,
        auth => auth()
    });
});

true;
