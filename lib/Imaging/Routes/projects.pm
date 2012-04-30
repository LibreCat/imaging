package Imaging::Routes::projects;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use URI::Escape qw(uri_escape);
use DateTime::Format::Strptime;
use Time::HiRes;
use Try::Tiny;
use List::MoreUtils qw(first_index);

sub core {
    state $core = store("core");
}
sub indexer {
    state $indexer = store("index");
}   
sub index_locations {
    state $index_locations = indexer->bag("locations");
}
sub projects {
    state $projects = core()->bag("projects");
}
hook before => sub {
    if(request->path =~ /^\/project(.*)$/o){
        my $auth = auth;
        my $authd = authd;
        my $subpath = $1;
        if(!$authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }elsif($subpath =~ /(?:add|edit|delete)/o && !$auth->can('projects','edit')){
            request->path_info('/access_denied');
            my $params = params;
            $params->{text} = "U beschikt niet over de nodige rechten om projectinformatie aan te passen"
        }
    }
};

any('/projects',sub {
    
    my $config = config;
    my $params = params;

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;

    my $projects = projects->slice($offset,$num)->to_array();
    
    my $page_info = Data::Pageset->new({
        'total_entries'       => projects->count,
        'entries_per_page'    => $num,
        'current_page'        => $page,
        'pages_per_set'       => 8,
        'mode'                => 'fixed'
    });
    template('projects',{
        page_info => $page_info,
        projects => $projects,
        auth => auth()
    }); 
});
any('/projects/add',sub{
    my $config = config;
    my $params = params;    
    my(@messages,@errors);
    my $success = 0;

    if($params->{submit}){
        #check empty string
        my @keys = qw(name name_subproject description date_start query);
        foreach my $key(@keys){
            if(!is_string($params->{$key})){
                push @errors,"$key is niet opgegeven";
            }
        }
        #check empty array
        @keys = qw();
        foreach my $key(@keys){
            if(is_string($params->{$key})){
                $params->{$key} = [$params->{$key}];
            }elsif(!is_array_ref($params->{$key})){
                $params->{$key} = [];
            }
            if(scalar( @{ $params->{$key} } ) == 0){
                push @errors,"$key is niet opgegegeven (een of meerdere)";
            }
        }
        #check format
        my %check = (
            date_start => sub{
                my $value = shift;
                my($success,$error)=(1,undef);
                try{
                    DateTime::Format::Strptime::strptime("%d-%m-%Y",$value);
                }catch{
                    say $_;
                    $success = 0;
                    $error = "invalid start date (day-month-year)";
                };  
                return $success,$error;
            }
        );  
        if(scalar(@errors)==0){
            foreach my $key(keys %check){
                my($success,$error) = $check{$key}->($params->{$key});
                push @errors,$error if !$success;
            }
        }
        #insert
        if(scalar(@errors)==0){
            my $project = projects->add({
                name => $params->{name},
                name_subproject => $params->{name_subproject},
                description => $params->{description},
                date_start => $params->{date_start},
                datetime_last_modified => Time::HiRes::time,
                query => $params->{query},
                locked => 0,
                list => []
            });
            redirect(uri_for("/projects"));
        }
    }

    template('projects/add',{
        errors => \@errors,
        messages => \@messages,
        success => $success,
        auth => auth()
    });
});
any('/project/:_id/edit',sub{
    my $config = config;
    my $params = params;
    my(@messages,@errors);
    my $success = 0;

    #check project existence
    my $project = projects->get($params->{_id});
    if(!$project){
        return forward('/not_found',{
            requested_path => request->path
        });
    }

    if($params->{submit}){
        if(!$project->{locked}){
            #check empty string
            my @keys = qw(name name_subproject description date_start query);
            foreach my $key(@keys){
                if(!is_string($params->{$key})){
                    push @errors,"$key is niet opgegeven";
                }
            }
            #check empty array
            @keys = qw();
            foreach my $key(@keys){
                if(is_string($params->{$key})){
                    $params->{$key} = [$params->{$key}];
                }elsif(!is_array_ref($params->{$key})){
                    $params->{$key} = [];
                }
                if(scalar( @{ $params->{$key} } ) == 0){
                    push @errors,"$key is niet opgegeven (een of meerdere)";
                }
            }
            #check format
            my %check = (
                date_start => sub{
                    my $value = shift;
                    my($success,$error)=(1,undef);
                    try{
                        DateTime::Format::Strptime::strptime("%d-%m-%Y",$value);
                    }catch{
                        say $_;
                        $success = 0;
                        $error = "startdatum is ongeldig (dag-maand-jaar)";
                    };
                    return $success,$error;
                }
            );
            if(scalar(@errors)==0){
                foreach my $key(keys %check){
                    my($success,$error) = $check{$key}->($params->{$key});
                    push @errors,$error if !$success;
                }
            }
            #insert
            if(scalar(@errors)==0){
                my $new = {
                    name => $params->{name},
                    name_subproject => $params->{name_subproject},
                    description => $params->{description},
                    date_start => $params->{date_start},
                    datetime_last_modified => Time::HiRes::time,
                    query => $params->{query}
                };
                $project = { %$project,%$new };
                projects->add($project);
                redirect(uri_for("/projects"));
            }
        }else{
            push @errors,"Sorry, dit project kan niet meer gewijzigd worden. Er zijn reeds scanobjecten aan gekoppeld.";
        }
    }

    template('project/edit',{
        errors => \@errors,
        messages => \@messages,
        success => $success,
        project => $project,
        auth => auth()
    });
});
any('/project/:_id/delete',sub{
    my $config = config;
    my $params = params;
    my(@messages,@errors);
    my $project;

    #check project exists
    if(!is_string($params->{_id})){
        push @errors,"identifier is niet opgegeven";
    }else{
        $project = projects->get($params->{_id});
        if(!$project){
            push @errors,"project '$params->{_id}' bestaat niet";
        }
    }
    #delete?
    if(scalar(@errors) == 0 && $params->{submit}){
        projects->delete($params->{_id});
        return redirect(uri_for("/projects"));  
    }

    template('project/delete',{
        errors => \@errors,
        messages => \@messages,
        project => $project,
        auth => auth()
    });
});

true;
