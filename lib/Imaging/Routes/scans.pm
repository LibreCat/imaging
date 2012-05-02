package Imaging::Routes::scans;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Meercat;
use Dancer::Plugin::NestedParams;
use Dancer::Plugin::Auth::RBAC;
use Dancer::Plugin::Database;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);

use Clone qw(clone);
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Time::HiRes;
use Digest::MD5 qw(md5_hex);
use File::Basename qw();

sub formatted_date {
    my $time = shift || Time::HiRes::time;
    DateTime::Format::Strptime::strftime(
        '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}


sub core {
    state $core = store("core");
}
sub indexer {
    state $index = store("index")->bag;
}
sub scans {
    state $scans = core()->bag("scans");
}
sub projects {
    state $projects = core()->bag("projects");
}
sub index_logs {
    state $index = store("index_log")->bag;
}
sub dbi_handle {
    state $dbi_handle = database;
}
sub status2index {
    my $scan = shift;
    my $doc;
    my $index_log = index_logs();
    my $owner = dbi_handle->quick_select("users",{ id => $scan->{user_id} });

    foreach my $history(@{ $scan->{status_history} || [] }){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{scan_id} = $scan->{_id};
        $doc->{owner} = $owner->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
    $index_log->commit;
    $doc;
}
sub marcxml_flatten {
    my $xml = shift;
    my $ref = from_xml($xml,ForceArray => 1);
    my @text = ();
    foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
        foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
            next if !is_string($marc_subfield->{content});
            push @text,$marc_subfield->{content};
        }
    }
    foreach my $control_field(@{ $ref->{'marc:controlfield'} }){
        next if !is_string($control_field->{content});
        push @text,$control_field->{content};
    }
    return \@text;
}
sub scan2index {
    my $scan = shift;

    my $doc = clone($scan);

    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} });
    $doc->{metadata_id} = \@metadata_ids;

    $doc->{text} = [];
    push @{ $doc->{text} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});


    my @deletes = qw(metadata comments busy busy_reason);
    delete $doc->{$_} foreach(@deletes);

    $doc->{files} = [ map { $_->{path} } @{ $scan->{files} || [] } ];

    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_name}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    my $project;
    if($scan->{project_id} && ($project = projects()->get($scan->{project_id}))){
        foreach my $key(keys %$project){
            next if $key eq "list";
            my $subkey = "project_$key";
            $subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }

    if($scan->{user_id}){
        my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
        if($user){
            $doc->{user_name} = $user->{name};
            $doc->{user_login} = $user->{login};
            $doc->{user_roles} = [split(',',$user->{roles})];
        }
    }

    foreach my $key(keys %$doc){
        next if $key !~ /datetime/o;
        $doc->{$key} = formatted_date($doc->{$key});
    }
    indexer->add($doc);
    indexer->commit;
    $doc;
}

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
    my $indexer = indexer();
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
    try {
        $result= indexer->search(%opts);
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
any('/scans/view/:_id/comments',,sub{
    my $params = params;
    my $auth = auth;
    my $config = config;
    my @errors = ();
    my @messages = ();
    my $scan = scans->get($params->{_id});
    $scan or return not_found();

    my $project;
    if($scan->{project_id}){
        $project = projects->get($scan->{project_id});
    }

    #comment - start
    if(is_string($params->{comment})){
        if($auth->can('scans','comment')){
            push @{ $scan->{comments} ||= [] },{
                datetime => Time::HiRes::time,
                text => $params->{comment},
                user_name => session('user')->{login}
            };
            scans->add($scan);
        }else{
            #complain
            push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";
        }
    }
    #comment - end

    template('scans/comments',{
        scan => $scan,
        auth => $auth,
        errors => \@errors,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $scan->{user_id} })
    }); 

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
                    user_name => session('user')->{login}
                };
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
        
            my $baginfo_params = expand_params->{baginfo} || {};

            my @conf_baginfo_keys = do {
                my $config = config;
                my @values = ();
                push @values,$_->{key} foreach(@{$config->{app}->{scan}->{edit}->{baginfo}});
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
