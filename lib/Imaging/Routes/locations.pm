package Imaging::Routes::locations;
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
    state $index = store("index")->bag("locations");
}
sub locations {
    state $locations = core()->bag("locations");
}
sub projects {
    state $projects = core()->bag("projects");
}
sub index_logs {
    state $index = store("index_log")->bag("log_locations");
}
sub dbi_handle {
    state $dbi_handle = database;
}
sub status2index {
    my $location = shift;
    my $doc;
    my $index_log = index_logs();
	my $owner = dbi_handle->quick_select("users",{ id => $location->{user_id} });

    foreach my $history(@{ $location->{status_history} || [] }){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{location_id} = $location->{_id};
        $doc->{owner} = $owner->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
	$index_log->commit;
    $doc;
}
sub location2index {
    my $location = shift;

    my $doc = clone($location);
    my @deletes = qw(metadata comments);
    delete $doc->{$_} foreach(@deletes);

    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_name}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    my $project;
    if($location->{project_id} && ($project = projects()->get($location->{project_id}))){
        foreach my $key(keys %$project){
            next if $key eq "list";
            my $subkey = "project_$key";
            $subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }

    if($location->{user_id}){
		my $user = dbi_handle->quick_select("users",{ id => $location->{user_id} });
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
    if(request->path =~ /^\/locations/o){
		if(!authd){
			my $service = uri_escape(uri_for(request->path));
			return redirect(uri_for("/login")."?service=$service");
		}
	}
};
any('/locations',sub {
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
    $opts{sort} = $sort if $sort && $sort =~ /^\w+\s(?:asc|desc)$/o;
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
        template('locations',{
            locations => $result->hits,
            page_info => $page_info,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }else{
        template('locations',{
            locations => [],
            errors => \@errors,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});
any('/locations/view/:_id',sub {
    my $params = params;
	my @errors = ();
	my $auth = auth;
	my $location = locations->get($params->{_id});
	$location or return not_found();

    my $project;
    if($location->{project_id}){
        $project = projects->get($location->{project_id});
    }

    template('locations/view',{
		location => $location,
        auth => $auth,
        errors => \@errors,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $location->{user_id} })
    });
});

any('/locations/edit/:_id',sub{
	my $params = params;
	my $auth = auth;
	my @errors = ();
	my @messages = ();
    my $location = locations->get($params->{_id});
    $location or return not_found();

	if(!($auth->asa('admin') || $auth->can('locations','edit'))){
        return forward('/access_denied',{
            text => "U mist de nodige gebruikersrechten om dit record te kunnen aanpassen"
        });
    }

    my $project;
    if($location->{project_id}){
        $project = projects->get($location->{project_id});
    }
	#edit - start 	
	if(!$location->{busy}){
		my($errs,$msgs);
		($location,$errs,$msgs) = edit_location($location);
		push @errors,@$errs;
		push @messages,@$msgs;
		if(scalar(@$errs)==0){
     	   locations->add($location);
    	}
	}
	#edit - end	
    template('locations/edit',{
        location => $location,
        auth => $auth,
        errors => \@errors,
		messages => \@messages,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $location->{user_id} })
    });

});
any('/locations/view/:_id/comments',,sub{
    my $params = params;
    my $auth = auth;
    my $config = config;
    my @errors = ();
    my @messages = ();
    my $location = locations->get($params->{_id});
    $location or return not_found();

	my $project;
    if($location->{project_id}){
        $project = projects->get($location->{project_id});
    }

	#comment - start
    if(is_string($params->{comment})){
        if($auth->can('locations','comment')){
            push @{ $location->{comments} ||= [] },{
                datetime => Time::HiRes::time,
                text => $params->{comment},
                user_name => session('user')->{login}
            };
            locations->add($location);
        }else{
            #complain
            push @errors,"U beschikt niet over de nodige rechten om commentaar toe te voegen";
        }
    }
    #comment - end

	template('locations/comments',{
        location => $location,
        auth => $auth,
        errors => \@errors,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $location->{user_id} })
    });	

});
any('/locations/edit/:_id/status',sub{
    my $params = params;
    my $auth = auth;
	my $config = config;
    my @errors = ();
    my @messages = ();
	my $mount_conf = mount_conf;
    my $location = locations->get($params->{_id});
    $location or return not_found();

    if(!($auth->asa('admin') || $auth->can('locations','edit'))){
        return forward('/access_denied',{
            text => "U mist de nodige gebruikersrechten om dit record te kunnen aanpassen"
        });
    }

    my $project;
    if($location->{project_id}){
        $project = projects->get($location->{project_id});
    }

	#edit status - begin
	if($params->{submit} && !$location->{busy}){
		my $comments = $params->{comments} // "";
		my $status_from = $location->{status};
		my @status_to_allowed = @{ $config->{status}->{change}->{qa_control}->{$status_from}->{'values'} || [] };
		my $status_to = $params->{status_to};
		if(!is_string($status_to)){
			push @errors,"gelieve de nieuwe status op te geven";
		}else{
			my $index = first_index { $_ eq $status_to } @status_to_allowed;
			if($index >= 0){
				#wijzig status
				$location->{status} = $status_to;
				#voeg toe aan status history	
				push @{ $location->{status_history} ||= [] },{
					user_name => session('user')->{login},
                    status => $status_to,
                    datetime => Time::HiRes::time,
                    comments => $comments
				};
				#neem op in comments
				my $text = "wijzing status $status_from naar $status_to";
				$text .= ":$comments" if $comments;
				push @{ $location->{comments} ||= [] },{
					datetime => Time::HiRes::time,
					text => $text,
					user_name => session('user')->{login}
				};
				locations->add($location);
				#locations
				location2index($location);
				#log
				status2index($location);

				if($status_to eq "reprocess_scans"){
					$location->{busy} = 1;
                    $location->{busy_reason} = "move";
					my $owner = dbi_handle->quick_select("users",{ id => $location->{user_id} });
					$location->{newpath} = $mount_conf->{mount}."/".$mount_conf->{subdirectories}->{reprocessing}."/".$owner->{login}."/".File::Basename::basename($location->{path});
					say $location->{newpath};
                    locations->add($location);
				}
				#redirect
				return redirect("/locations/edit/$location->{_id}");
			}else{
				push @errors,"status kan niet worden gewijzigd van $status_from naar $status_to";
			}
		}
	}
	#edit status - einde

	template('locations/status',{
        location => $location,
        auth => $auth,
        errors => \@errors,
        messages => \@messages,
        mount_conf => mount_conf(),
        project => $project,
        user => dbi_handle->quick_select('users',{ id => $location->{user_id} })
    });
});

sub edit_location {
	my $location = shift;
	my $params = params;
	my @errors = ();
	my @messages = ();
	my $action = $params->{action} || "";

	$location->{metadata} ||= [];

	#past metadata_id aan => verwacht dat er 0 of 1 element in 'metadata' zit
	if($action eq "edit_metadata_id"){
		
		if(is_array_ref($location->{metadata}) && scalar(@{$location->{metadata}}) > 1){

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
					$location->{metadata} = [{
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
			my $index = first_index { $_->{source}.":".$_->{fSYS} eq $params->{metadata_id} } @{$location->{metadata}};
			if($index >= 0){
				splice @{$location->{metadata}},$index,1;
				push @messages,"metadata_id $params->{metadata_id} werd verwijderd";
			}
		}
	}
	#voeg dc-elementen toe
	elsif($action eq "add_baginfo_pair"){

		if(is_array_ref($location->{metadata}) && scalar(@{$location->{metadata}}) > 1){

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
				$location->{metadata}->[0]->{baginfo}->{$key} ||= [];
				push @{ $location->{metadata}->[0]->{baginfo}->{$key} },$value;
				push @messages,"baginfo werd aangepast";
			}

		}
	}elsif($action eq "edit_baginfo"){
		if(is_array_ref($location->{metadata}) && scalar(@{$location->{metadata}}) > 1){

            push @errors,"Dit record bevat meerdere metadata records. Verwijder eerst de overbodige.";

        }else{
		
			my $baginfo_params = expand_params->{baginfo} || {};

			my @conf_baginfo_keys = do {
				my $config = config;
				my @values = ();
				push @values,$_->{key} foreach(@{$config->{app}->{location}->{edit}->{baginfo}});
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
				$location->{metadata}->[0]->{baginfo} = $baginfo;
				push @messages,"baginfo werd aangepast";
			}
		}
	}
	return $location,\@errors,\@messages;
}


true;