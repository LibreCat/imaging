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
sub index_scans {
    state $index_scans = indexer->bag;
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

    my $projects = projects->to_array();

    if(is_string($params->{'sort'}) && $params->{'sort'} =~ /^(\w+)\s(?:asc|desc)$/o){
        my($sort_key,$sort_dir)=($1,$2);
        if(is_string($projects->[0]->{$sort_key})){
            our($a,$b); 
            $projects = [ sort {
                if(is_number($a->{$sort_key})){
                    return ( $a->{$sort_key} <=> $b->{$sort_key} );       
                }else{
                    return ( $a->{$sort_key} cmp $b->{$sort_key} );
                }
            } @$projects ];
        }
        if($sort_dir eq "desc"){
            $projects = [reverse(@$projects)];
        }
    }
    
    $projects =  [splice(@$projects,$offset,$num)];

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
        my @keys = qw(name name_subproject description datetime_start query);
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
            datetime_start => sub{
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
            $params->{datetime_start} =~ /^(\d{2})-(\d{2})-(\d{4})$/o;
            say to_dumper($params);
            say "day:$1, month:$2, year:$3";
            my $datetime = DateTime->new( day => int($1), month => int($2), year => int($3));
            my $project = projects->add({
                name => $params->{name},
                name_subproject => $params->{name_subproject},
                description => $params->{description},
                datetime_start => $datetime->epoch,
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
            my @keys = qw(name name_subproject description datetime_start query);
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
                datetime_start => sub{
                    my $value = shift;
                    my($success,$error)=(1,undef);
                    try{
                        my $datetime = DateTime::Format::Strptime::strptime("%d-%m-%Y",$value);
                        
                    }catch{
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
                $params->{datetime_start} =~ /^(\d{2})-(\d{2})-(\d{4})$/o;
                my $datetime = DateTime->new( day => int($1), month => int($2), year => int($3));
                my $new = {
                    name => $params->{name},
                    name_subproject => $params->{name_subproject},
                    description => $params->{description},
                    datetime_start => $datetime->epoch,
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
