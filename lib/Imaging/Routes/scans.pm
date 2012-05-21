package Imaging::Routes::scans;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Meercat;
use Dancer::Plugin::Imaging::Routes::Utils;
use CGI::Expand qw(expand_hash);
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);
use Time::HiRes;
use File::Basename qw();
use Data::UUID;

hook before => sub {
    if(request->path =~ /^\/scans/o){
        if(!authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }
    }
};
any('/scans',sub {
    my $params = params;
    my $index_scan = index_scan();
    my $q = is_string($params->{q}) ? $params->{q} : "*";

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;
    my $sort = $params->{sort};

    my %opts = (
        query => $q,
        start => $offset,
        limit => $num
    );
    if(is_string($sort)){
        $opts{sort} = [ $sort ] if $sort =~ /^\w+\s(?:asc|desc)$/o;
    }elsif(is_array_ref($sort)){
        my $ok = 1;
        foreach(@$sort){
            if($_ !~ /^\w+\s(?:asc|desc)$/o){
                $ok = 0;
                last;
            }
        }
        if($ok){
            $opts{sort} = $sort;
        }
    }
    my @errors = ();
    my($result);
    my $facets = [];
    try {
        my $facet_fields = config->{app}->{scans}->{facet_fields};
        if(is_array_ref($facet_fields) && scalar(@$facet_fields) > 0){
            $opts{facet} = "true";
            $opts{"facet.field"} = $facet_fields;
        }
        $result= $index_scan->search(%opts);
        $facets = $result->{facets};
    }catch{
        push @errors,"ongeldige zoekvraag";
    };
    if(scalar(@errors)==0){
        my $page_info = Data::Pageset->new({
            'total_entries'       => $result->total,
            'entries_per_page'    => $num,
            'current_page'        => $page,
            'pages_per_set'       => 8,
            'mode'                => 'fixed'
        });
        template('scans',{
            scans => $result->hits,
            facets => $facets,
            page_info => $page_info,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }else{
        template('scans',{
            scans => [],
            errors => \@errors,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});
any('/scans/view/:_id',sub {
    my $params = params;
    my @errors = ();
    my $auth = auth;
    my $scan = scans->get($params->{_id});
    $scan or return not_found();

    my $project;
    if($scan->{project_id}){
        $project = projects->get($scan->{project_id});
    }
    my $files = $scan->{files} || [];
    our($a,$b);
    $files = [sort {
        $a->{name} cmp $b->{name};
    } @$files];
    $scan->{files} = $files;

    template('scans/view',{
        scan => $scan,
        auth => $auth,
        errors => \@errors,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $scan->{user_id} })
    });
});

any('/scans/edit/:_id',sub{
    my $params = params;
    my $auth = auth;
    my @errors = ();
    my @messages = ();
    my $scan = scans->get($params->{_id});
    $scan or return not_found();

    if(!($auth->asa('admin') || $auth->can('scans','edit'))){
        return forward('/access_denied',{
            text => "U mist de nodige gebruikersrechten om dit record te kunnen aanpassen"
        });
    }

    my $project;
    if($scan->{project_id}){
        $project = projects->get($scan->{project_id});
    }
    #edit - start   
    if(!$scan->{busy}){
        my($errs,$msgs);
        ($scan,$errs,$msgs) = edit_scan($scan);
        push @errors,@$errs;
        push @messages,@$msgs;
        if(scalar(@$errs)==0){
            scans->add($scan);
            scan2index($scan);
        }
    }

    my $files = $scan->{files} || [];
    our($a,$b);
    $files = [sort {
        $a->{name} cmp $b->{name};
    } @$files];
    $scan->{files} = $files;

    #edit - end 
    template('scans/edit',{
        scan => $scan,
        auth => $auth,
        errors => \@errors,
        messages => \@messages,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $scan->{user_id} })
    });

});
any('/scans/comments/:_id',,sub{
    my $params = params;
    my @errors = ();
    my @messages = ();
    my $scan = scans->get($params->{_id});

    my $comments = [];
    
    content_type 'json';    

    my $response = { };

    if(!$scan){

        push @errors, "scandirectory $params->{_id} niet gevonden";

    }else{
        
        $comments = $scan->{comments};
                
    }

    $response->{status} = scalar(@errors) == 0 ? "ok":"error";
    $response->{errors} = \@errors;
    $response->{messages} = \@messages;
    $response->{data} = $comments;

    return to_json($response);
});

any('/scans/comments/:_id/add',,sub{
    my $params = params;
    my $auth = auth;
    my $config = config;
    my @errors = ();
    my @messages = ();
    my $scan = scans->get($params->{_id});
    
    my $comment;

    content_type 'json';    

    my $response = { };

    if(!$scan){

        push @errors, "scandirectory $params->{_id} niet gevonden";

    }elsif(!$auth->can('scans','comment')){

        push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";

    }elsif(!is_string($params->{text})){
        
        push @errors,"parameter 'text' is leeg";

    }else{

        $comment = {
            datetime => Time::HiRes::time,
            text => $params->{text},
            user_name => session('user')->{login},
            id => Data::UUID->new->create_str
        };
        push @{ $scan->{comments} ||= [] },$comment;
        scans->add($scan);

    }

    $response->{status} = scalar(@errors) == 0 ? "ok":"error";
    $response->{errors} = \@errors;
    $response->{messages} = \@messages;
    $response->{data} = $comment;

    return to_json($response);
});
#any('/scans/comments/:_id/delete',,sub{
#    my $params = params;
#    my $auth = auth;
#    my $config = config;
#    my @errors = ();
#    my @messages = ();
#    my $scan = scans->get($params->{_id});
#    
#    my $comment;
#
#    content_type 'json';    
#
#    my $response = { };
#
#    if(!$scan){
#
#        push @errors, "scandirectory $params->{_id} niet gevonden";
#
#    }elsif(!$auth->can('scans','comment')){
#
#        push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";
#
#    }elsif(!is_string($params->{comment_id})){
#        
#        push @errors,"parameter 'comment_id' is leeg";
#
#    }else{
#        my $index = first_index {
#            $_->{id} == $params->{comment_id};
#        } @{ $scan->{comments} || [] };
#
#        if($index >= 0){
#
#            my $login = session('user')->{login};
#            if($auth->asa('admin') || $login eq $scan->{comments}->[$index]->{user_name}){
#
#                splice(@{ $scan->{comments} },$index,1);
#                push @messages,"comment is verwijderd";
#                scans->add($scan);
#
#            }else{
#                push @errors,"U beschikt niet over de nodige rechten om deze comment te verwijderen";
#            }
#        }else{
#            push @errors,"comment niet gevonden";
#        }
#
#    }
#
#    $response->{status} = scalar(@errors) == 0 ? "ok":"error";
#    $response->{errors} = \@errors;
#    $response->{messages} = \@messages;
#
#    return to_json($response);
#});
any('/scans/comments/:_id/clear',,sub{
    my $params = params;
    my $auth = auth;
    my $config = config;
    my @errors = ();
    my @messages = ();
    my $scan = scans->get($params->{_id});
    
    my $comment;

    content_type 'json';    

    my $response = { };

    if(!$scan){

        push @errors, "scandirectory $params->{_id} niet gevonden";

    }elsif(!$auth->asa('admin')){

        push @errors,"U beschikt niet over de nodige rechten om alle commentaren te wissen";

    }else{

        $scan->{comments} = [];
        scans->add($scan);

    }

    $response->{status} = scalar(@errors) == 0 ? "ok":"error";
    $response->{errors} = \@errors;
    $response->{messages} = \@messages;

    return to_json($response);
});

any('/scans/edit/:_id/status',sub{
    my $params = params;
    my $auth = auth;
    my $config = config;
    my @errors = ();
    my @messages = ();
    my $mount_conf = mount_conf;
    my $scan = scans->get($params->{_id});
    $scan or return not_found();

    if(!($auth->asa('admin') || $auth->can('scans','edit'))){
        return forward('/access_denied',{
            text => "U mist de nodige gebruikersrechten om dit record te kunnen aanpassen"
        });
    }

    my $project;
    if($scan->{project_id}){
        $project = projects->get($scan->{project_id});
    }

    #edit status - begin
    if($params->{submit} && !$scan->{busy}){
        my $comments = $params->{comments} // "";
        my $status_from = $scan->{status};
        my @status_to_allowed = @{ $config->{status}->{change}->{qa_control}->{$status_from}->{'values'} || [] };
        my $status_to = $params->{status_to};
        if(!is_string($status_to)){
            push @errors,"gelieve de nieuwe status op te geven";
        }else{
            my $index = first_index { $_ eq $status_to } @status_to_allowed;
            if($index >= 0){
                #wijzig status
                $scan->{status} = $status_to;
                #voeg toe aan status history    
                push @{ $scan->{status_history} ||= [] },{
                    user_name => session('user')->{login},
                    status => $status_to,
                    datetime => Time::HiRes::time,
                    comments => $comments
                };
                #neem op in comments
                my $text = "wijzing status $status_from naar $status_to";
                $text .= ":$comments" if $comments;
                push @{ $scan->{comments} ||= [] },{
                    datetime => Time::HiRes::time,
                    text => $text,
                    user_name => session('user')->{login},
                    id => Data::UUID->new->create_str
                };
                $scan->{datetime_last_modified} = Time::HiRes::time;
                scans->add($scan);
                #scan
                scan2index($scan);
                #log
                status2index($scan);

                if($status_to eq "reprocess_scans"){
                    $scan->{busy} = 1;
                    $scan->{busy_reason} = "move";
                    my $owner = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
                    $scan->{newpath} = $mount_conf->{mount}."/".$mount_conf->{subdirectories}->{reprocessing}."/".$owner->{login}."/".File::Basename::basename($scan->{path});
                    scans->add($scan);
                }
                #redirect
                return redirect("/scans/view/$scan->{_id}");
            }else{
                push @errors,"status kan niet worden gewijzigd van $status_from naar $status_to";
            }
        }
    }
    #edit status - einde

    template('scans/status',{
        scan => $scan,
        auth => $auth,
        errors => \@errors,
        messages => \@messages,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $scan->{user_id} })
    });
});

sub edit_scan {
    my $scan = shift;
    my $params = params;
    my @errors = ();
    my @messages = ();
    my $action = $params->{action} || "";

    $scan->{metadata} ||= [];

    #past metadata_id aan => verwacht dat er 0 of 1 element in 'metadata' zit
    if($action eq "edit_metadata_id"){
        
        if(is_array_ref($scan->{metadata}) && scalar(@{$scan->{metadata}}) > 1){

            push @errors,"Dit record bevat meerdere metadata records. Verwijder eerst de overbodige.";

        }else{

            my @keys = qw(metadata_id);
            foreach my $key(@keys){
                if(!is_string($params->{$key})){
                    push @errors,"$key is niet opgegeven";
                }       
            }
            if(scalar(@errors)==0){
                my($result,$total,$error);
                try {

                    $result = meercat->search($params->{metadata_id});      
                    $total = $result->content->{response}->{numFound};

                }catch{
                    $error = $_;
                    print $_;
                };
                if($error){
                    push @errors,"query $params->{metadata_id_to} is ongeldig";
                }elsif($total > 1){
                    push @errors,"query $params->{metadata_id_to} leverde meer dan één resultaat op";
                }elsif($total == 0){
                    push @errors,"query $params->{metadata_id_to} leverde geen resultaten op";
                }else{
                    my $doc = $result->content->{response}->{docs}->[0];
                    $scan->{metadata} = [{
                        fSYS => $doc->{fSYS},#000000001
                        source => $doc->{source},#rug01
                        fXML => $doc->{fXML},
                        baginfo => marcxml2baginfo($doc->{fXML})            
                    }];
                    push @messages,"metadata identifier werd aangepast";
                }
            }
        }
    }
    #verwijder element met metadata_id uit de lijst (mag resulteren in 0 elementen)
    elsif($action eq "delete_metadata_id"){

        my @keys = qw(metadata_id);
        foreach my $key(@keys){
            if(!is_string($params->{$key})){
                push @errors,"$key is niet opgegeven";
            }
        }
        if(scalar(@errors)==0){
            my $index = first_index { $_->{source}.":".$_->{fSYS} eq $params->{metadata_id} } @{$scan->{metadata}};
            if($index >= 0){
                splice @{$scan->{metadata}},$index,1;
                push @messages,"metadata_id $params->{metadata_id} werd verwijderd";
            }
        }
    }
    #voeg dc-elementen toe
    elsif($action eq "add_baginfo_pair"){

        if(is_array_ref($scan->{metadata}) && scalar(@{$scan->{metadata}}) > 1){

            push @errors,"Dit record bevat meerdere metadata records. Verwijder eerst de overbodige.";

        }else{

            my @keys = qw(key value);
            foreach my $key(@keys){
                if(!is_string($params->{$key})){
                    push @errors,"gelieve een waarde op te geven";
                    last;
                }
            }
            if(scalar(@errors)==0){
                my $key = $params->{key};
                my $value = $params->{value};
                $scan->{metadata}->[0]->{baginfo}->{$key} ||= [];
                push @{ $scan->{metadata}->[0]->{baginfo}->{$key} },$value;
                push @messages,"baginfo werd aangepast";
            }

        }
    }elsif($action eq "edit_baginfo"){
        if(is_array_ref($scan->{metadata}) && scalar(@{$scan->{metadata}}) > 1){

            push @errors,"Dit record bevat meerdere metadata records. Verwijder eerst de overbodige.";

        }else{
            my $expanded_params = expand_hash($params || {});
            my $baginfo_params = $expanded_params->{baginfo} || {};

            my @conf_baginfo_keys = do {
                my $config = config;
                my @values = ();
                push @values,$_->{key} foreach(@{$config->{app}->{scans}->{edit}->{baginfo}});
                @values;
            };

            my $baginfo = {};
            foreach my $key(sort keys %$baginfo_params){    
                my $index = first_index { $key eq $_ } @conf_baginfo_keys;
                if($index >= 0){
                    $baginfo->{$key} = is_array_ref($baginfo_params->{$key}) ? $baginfo_params->{$key}: [$baginfo_params->{$key}];
                }else{
                    push @errors,"$key is een ongeldige key voor baginfo";
                }
            }
            if(scalar(@errors)==0){
                $scan->{metadata}->[0]->{baginfo} = $baginfo;
                push @messages,"baginfo werd aangepast";
            }
        }
    }
    return $scan,\@errors,\@messages;
}

true;
