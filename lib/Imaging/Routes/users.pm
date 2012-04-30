package Imaging::Routes::users;
use Dancer  ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu    qw(store);
use Catmandu::Util  qw(:is);
use URI::Escape qw(uri_escape);
use Digest::MD5 qw(md5_hex);
use File::Path  qw(mkpath   rmtree);
use Try::Tiny;

sub dbi_handle {
    state $dbi_handle = database;
}
sub core {
    state $core = store("core");
}
sub profiles {
    state $profiles = core()->bag("profiles");
}
hook before => sub {
    if(request->path    =~  /^\/user/o){
        my  $auth   =   auth;
        my  $authd  =   authd;
        if(!$authd){
            my  $service    =   uri_escape(uri_for(request->path));
            return  redirect(uri_for("/login")."?service=$service");
        }elsif(!$auth->can('manage_accounts','edit')){
            request->path_info('/access_denied');
            my  $params =   params;
            $params->{text} =   "U  beschikt    niet    over    de  nodige  rechten om  gebruikersinformatie    aan te  passen";
        }
    }
};  
any('/users',sub{

    my  @users  =   dbi_handle->quick_select('users',{},{   order_by    =>  'id'    });
    template('users',{
        users   =>  \@users,
        auth    =>  auth()
    });

});
any('/users/add',sub{

    my  $params =   params;
    my(@errors,@messages);
    if($params->{submit}){
        my($success,$errs)=check_params_new_user();
        push    @errors,@$errs;
        if(!(
                            is_string($params->{password1}) &&  is_string($params->{password2}) &&
                                                $params->{password1}    eq  $params->{password2}
            )
        ){
            push    @errors,"paswoorden komen   niet    met elkaar  overeen";
        }
        if(scalar(@errors)==0){
            my  $user   =   dbi_handle->quick_select('users',{  login   =>  $params->{login}    });
            if($user){
                push    @errors,"er bestaat reeds   een gebruiker   met als login   $params->{login}";
            }else{
                my  $roles  =   join('',@{  $params->{roles}    });
                dbi_handle->quick_insert('users',{
                    login   =>  $params->{login},
                    name    =>  $params->{name},
                    roles   =>  join(', ',@{    $params->{roles}    }),
                    password    =>  md5_hex($params->{password1}),
                    profile_id  =>  $params->{profile_id}
                });
                redirect(uri_for("/users"));
            }
        }
    }
    
                template('users/add',{
                                errors  =>  \@errors,
        messages    =>  \@messages,
        auth    =>  auth(),
        profiles    =>  profiles()->to_array
                });

});
any('/user/:id/edit',sub{

                my  $params =   params;
                my  $user   =   dbi_handle()->quick_select('users',{    id  =>  $params->{id}   });
    $user   or  return  not_found();

    if($user->{login}   eq  "admin"){
                                return  forward("/access_denied",{
            text    =>  "user   has not the right   to  edit    user    information"
                                });
                }

                my(@errors,@messages);

                if($params->{submit}){
        my($success,$errs)=check_params_new_user();
                                push    @errors,@$errs;     
                                if(scalar(@errors)==0){
            my  $roles  =   join(', ',@{    $params->{roles}    });
            my  $new    =   {
                roles   =>  $roles,
                login   =>  $params->{login},
                name    =>  $params->{name}
            };
            $new->{profile_id}  =   $params->{profile_id}   if  defined($params->{profile_id});
            #nieuw  wachtwoord  opgegeven?  ->  check!
            if($params->{edit_passwords}){
                if(!(
                    is_string($params->{password1}) &&  
                    is_string($params->{password2}) &&
                    $params->{password1}    eq  $params->{password2}
                    )
                ){
                    push    @errors,"paswoorden komen   niet    met elkaar  overeen";
                }else{
                    $new->{password}    =   md5_hex($params->{password1});
                }
            }
            if(scalar(@errors)==0){
                $user   =   {   %$user,%$new    };
                                                    dbi_handle->quick_update('users',{  id  =>  $params->{id}   },$user);
                redirect(uri_for("/users"));
            }
                                }
                }
                template('user/edit',{  
        user    =>  $user,
        errors  =>  \@errors,
        messages    =>  \@messages, 
        auth    =>  auth(),
        profiles    =>  profiles()->to_array
    });
});
any('/user/:id/delete',sub{

                my  $params =   params;
    my  $user   =   dbi_handle->quick_select('users',{  id  =>  $params->{id}   });
    $user   or  return  not_found();

                my(@errors,@messages);

    if($user->{login}   eq  "admin"){
        return  forward("/access_denied",{
            text    =>  "user   has not the right   to  edit    user    information"
                                });
    }
                if($params->{submit}){
                                dbi_handle->quick_delete('users',{
                                                id  =>  $params->{id}
                                });
        redirect(uri_for("/users"));
                }

                template('user/delete',{
                                errors  =>  \@errors,
                                messages    =>  \@messages,
        user    =>  $user,
        auth    =>  auth()
                });

});
sub check_params_new_user   {
    my  $params =   params;
    my(@errors);
    my  @keys   =   qw(name login);
                foreach my  $key(@keys){
                                if(!is_string($params->{$key})){
                                                push    @errors,"$key   is  niet    opgegeven"
                                }
                }
                @keys   =   qw(roles);
                foreach my  $key(@keys){
        if(is_string($params->{$key})){
            $params->{$key} =   [$params->{$key}];
        }elsif(!is_array_ref($params->{$key})){
            $params->{$key} =   [];
        }
                                if(!(scalar(@{  $params->{$key} })  >   0)){
                                                push    @errors,"$key   is  niet    opgegeven"
                                }
                }
    if(scalar(@errors)==0){
        my  $is_scanner =   scalar(grep {   $_  =~  /scanner/o  }   @{$params->{roles}})    >   0;
        if($is_scanner){
            my  $profile;
            if(!is_string($params->{profile_id})){
                push    @errors,"geen   profiel opgegeven,  hoewel  rol van scanner";
            }elsif(!($profile   =   profiles->get($params->{profile_id}))){
                push    @errors,"opgegeven  profiel bestaat niet";
            }
        }
    }
    return  scalar(@errors)==0,\@errors;
}

true;
