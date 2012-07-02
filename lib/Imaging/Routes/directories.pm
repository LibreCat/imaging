package Imaging::Routes::directories;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use Data::Pageset;
use URI::Escape qw(uri_escape);
use IO::CaptureOutput qw(capture_exec);

hook before => sub {
    if(request->path =~ /^\/directories/o){
        my $auth = auth;
        my $authd = authd;
        if(!$authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }elsif(!$auth->can('directories','edit')){
            request->path_info('/access_denied');
            my $params = params;
            $params->{text} = "u mist de nodige rechten om de scandirectories aan te passen";
        }
    }
};
any('/directories',sub {
    my $config = config;
    my $params = params;
    my(@errors)=();

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;

    my @users = dbi_handle->quick_select('users',{},{ order_by => 'id' });
    my $total = scalar(@users);
    @users = splice(@users,$offset,$num);

    my $page_info = Data::Pageset->new({
        'total_entries'       => $total,
        'entries_per_page'    => $num,
        'current_page'        => $page,
        'pages_per_set'       => 8,
        'mode'                => 'fixed'
    });
    #sanity check on mount
    my($success,$errs) = sanity_check();
    push @errors,@$errs if !$success;

    my $mount = mount();
    my $subdirectories = subdirectories();

    foreach my $user(@users){
        $user->{ready} = "$mount/".$subdirectories->{ready}."/".$user->{login};
    }
    #template
    template('directories',{
        users => \@users,
        errors => \@errors,
        page_info => $page_info,
        auth => auth()
    });
});
any('/directories/:id/edit',sub {
    my $config = config;
    my $params = params;
    my(@errors,@messages);
    my $user = dbi_handle->quick_select('users',{ id => $params->{id} });
    $user or return not_found();    

    #sanity check on mount
    my($success,$errs) = sanity_check();
    push @errors,@$errs if !$success;

    my $mount = mount();
    my $subdirectories = subdirectories();

    #check directories
    $user->{ready} = "$mount/".$subdirectories->{ready}."/".$user->{login};

    if($params->{submit} && scalar(@errors)==0){
        foreach(qw(ready)){
            try{
                my $path = "$mount/".$subdirectories->{$_}."/".$user->{login};
                if(!-d $path){
                    mkpath($path);
                }                
                my($stdout,$stderr,$success,$exit_code) = capture_exec("chown -R $user->{login} $path && chmod -R 0755 $path");
                die($stderr) if !$success;
                push @messages,"directory '$_' is ok nu";
                dbi_handle->quick_update('users',{ id => $user->{id} },{ has_dir => 1 });
            }catch{
                push @errors,$_;
            };
        }
    }else{
        foreach(qw(ready)){
            if(!-d $user->{$_}){
                push @errors,"directory '$_' bestaat niet ($user->{$_})";
            }elsif(!-w $user->{$_}){
                push @errors,"systeem kan niet schrijven naar directory '$_' ($user->{$_})";
            }
        }
    }

    template('directories/edit',{
        errors => \@errors,
        messages => \@messages,
        user => $user,
        auth => auth()
    });
});

true;
