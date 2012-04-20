#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use Try::Tiny;
use DBI;
use Clone qw(clone);
use DateTime;
use DateTime::Format::Strptime;
use WebService::Solr;
use Digest::MD5 qw(md5_hex);

#variabelen
sub store_opts {
	state $opts = {
		data_source => "dbi:mysql:database=imaging",
        username => "imaging",
        password => "imaging"
	};
}
sub store {
	state $store = Catmandu::Store::DBI->new(%{ store_opts() });
}
sub projects {
	state $projects = store()->bag("projects");
}
sub locations {
	state $locations = store()->bag("locations");
}
sub profiles {
	state $profiles = store()->bag("profiles");
}
sub meercat {
	state $meercat = WebService::Solr->new(
        "http://localhost:4000/solr",{default_params => {wt => 'json'}}
    );
}
sub index_locations {
	state $index_locations = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core0"
    )->bag("locations");
}
sub index_log {
	state $index_log = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core1"
    )->bag("log_locations");
}
sub mount_conf {
	state $mount_conf = do {
		my $dir = dirname(__FILE__);
		my $conf = YAML::LoadFile("$dir/../environments/development.yml");
	    my $mount_conf = $conf->{mounts}->{directories};
	};
}
sub users {
	state $users = do {
		my $opts = store_opts();
		DBI->connect($opts->{data_source}, $opts->{username}, $opts->{password}, {
        	AutoCommit => 1,
        	RaiseError => 1,
        	mysql_auto_reconnect => 1
    	});
	};
}
sub users_each {
	state $users_each = users->prepare("select * from users where roles like '%scanner'");
}
sub users_get {
	state $users_get = users->prepare("select * from users where id = ?");
}

sub formatted_date {
	my $time = shift || time;
	DateTime::Format::Strptime::strftime(
		'%FT%TZ', DateTime->from_epoch(epoch=>$time)
	);
}
sub status2index {
	my $location = shift;
	my $doc;
	my $index_log = index_log();
	foreach my $history(@{ $location->{status_history} || [] }){
		$doc = clone($history);
		$doc->{datetime} = formatted_date($doc->{datetime});
		$doc->{location_id} = $location->{_id};
		my $blob = join('',map { $doc->{$_} } sort keys %$doc);
		$doc->{_id} = md5_hex($blob);
		$index_log->add($doc);
	}
	$doc;
}
sub location2index {
	my $location = shift;		

	my $doc = clone($location);
	delete $doc->{metadata};

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
		my $users_get = users_get();
		$users_get->execute( $location->{user_id} ) or die($users_get->errstr);
		my $user = $users_get->fetchrow_hashref();
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

	index_locations()->add($doc);
	$doc;
}

#stap 1: gooi records waarvan de directory niet meer bestaat (door naamwijziging in het systeem)
say "\ndeleting bad locations from database\n";
my @bad_locations = ();
locations()->each(sub{
    my $location = shift;
    push @bad_locations,$location->{_id} if !(-d $location->{path});
});
foreach my $id(@bad_locations){
    say "location $id deleted from database";
    locations()->delete($id);
}


#stap 2: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "\nupdating list locations for projects:\n";
my @project_ids = ();
projects()->each(sub{ 
	push @project_ids,$_[0]->{_id}; 
});

foreach my $project_id(@project_ids){

    my $project = projects()->get($project_id);
	my $total = 0;

    my $query = $project->{query};
    next if !$query;

	my @list = ();

	my $meercat = meercat();
	my $res = $meercat->search($query,{rows=>0});
	$total = $res->content->{response}->{numFound};

	my($offset,$limit) = (0,1000);
	while($offset <= $total){
		$res = $meercat->search($query,{start => $offset,rows => $limit});
		my $hits = $res->content->{response}->{docs};

		foreach my $hit(@$hits){
			if(is_array_ref($hit->{location}) && scalar(@{ $hit->{location} }) > 0){
				push @list,@{$hit->{location}};
			}else{
				#piranesi-collectie heeft bijvoorbeeld geen plaatsnummers
				push @list,$hit->{source}.":".$hit->{fSYS};
			}
			say "\t".$list[-1] if @list;
		}
		$offset += $limit;
	}

	#op éénzelfde locatie kunnen soms meerdere items liggen: dus zoekquery naar locatie kan dus meerdere records opleveren!!
	#maak lijst dus uniek!
	my %uniq = ();
	$uniq{$_} = 1 foreach(@list);
	@list = keys %uniq;
	$project->{list} = \@list;
	$project->{datetime_last_modified} = time;
	$project->{locked} = 1;

	projects()->add($project);
};

#stap 3: ken locations toe aan projects
say "\nassigning locations to projects\n";
projects()->each(sub{
	my $project = shift;
	if(!is_array_ref($project->{list})){
		say "\tproject $project->{_id}: no list available";
		return;
	}
	foreach my $location_id(@{ $project->{list} }){
		my $location_dir = $location_id;
		if($location_dir =~ /^rug01:\d{9}$/o){
			$location_dir =~ s/rug01:/RUG01-/go;
		}else{
			$location_dir =~ s/[\.\/]/-/go;	
		}
		my $location = locations()->get($location_dir);

		#directory nog niet aanwezig
		if(!$location){
			say "\tproject ".$project->{_id}.":location $location_dir not found";
			next;
		}

        #location toekennen aan project
		if(!$location->{project_id}){
			$location->{name} = $location_id;
	        $location->{project_id} = $project->{_id};
		}

		say "\tproject ".$project->{_id}.":location $location_dir assigned to project";
		locations()->add($location);

	}
});
#stap 4: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
say "\nretrieving metadata for good locations:\n";
my @ids_ok_for_metadata = ();
locations()->each(sub{
	my $location = shift;
	my $status = $location->{status};
	my $metadata = $location->{metadata};
	if(	$status ne "incoming" && $status ne "incoming_error" && !(is_array_ref($metadata) && scalar(@$metadata) > 0 )){
		push @ids_ok_for_metadata,$location->{_id};
	}
});
foreach my $id(@ids_ok_for_metadata){
	my $location = locations()->get($id);
	my $query = $location->{_id};
	if($query !~ /^RUG01-/o){
		$query =~ s/^RUG01-/rug01:/o;
	}else{
		$query = "location:$query";
	}
	my $res = meercat()->search($query,{rows=>1000});
	$location->{metadata} = [];
    if($res->content->{response}->{numFound} > 0){

        my $docs = $res->content->{response}->{docs};
        foreach my $doc(@$docs){
            push @{ $location->{metadata} },{
                fSYS => $doc->{fSYS},#000000001
                source => $doc->{source},#rug01
                fXML => $doc->{fXML}
            };
        }

    }
	my $num = scalar(@{$location->{metadata}});
	say "\tlocation ".$location->{_id}." has $num metadata-records";
	locations()->add($location);
}

#stap 5: registreer locations die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
locations()->each(sub{
	my $location = shift;
	push @incoming_ok,$location->{_id} if $location->{status} eq "incoming_ok";
});
say "\nregistering incoming_ok\n";
foreach my $id (@incoming_ok){
	my $location = locations()->get($id);
	say "\tlocation $id:";

	#status 'registering'
	$location->{status} = "registering";
	push @{ $location->{status_history} },{
		user_name =>"-",
		status => "registering",
		datetime => time,
		comments => ""
	};

	#=> registratie kan lang duren (move!), waardoor map uit /ready verdwijnt, maar ondertussen ook in /locations is terug te vinden
	#=> daarom opnemen in databank én indexeren
	locations->add($location);
	location2index($location);
	index_locations->commit();

	status2index($location);
	index_log->commit();

	#pas manifest -> maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)
		
	#verwijder oude manifest vóóraf, want anders duikt oude manifest op in ... manifest.txt
	unlink($location->{path}."/manifest.txt") if -f $location->{path}."/manifest.txt";
	my $index = first_index { $_ eq $location->{path}."/manifest.txt" } @{ $location->{files} };
	splice(@{ $location->{files} },$index,1) if $index >= 0;

	say "\tcreating new manifest.txt";

	#maak nieuwe manifest
	local(*MANIFEST);
	open MANIFEST,">".$location->{path}."/manifest.txt" or die($!);
	foreach my $file(@{ $location->{files} }){
		local(*FILE);
		open FILE,$file or die($!);
		my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
		say MANIFEST "$md5sum_file ".basename($file);
		close FILE;
	}
	close MANIFEST;

	#voeg manifest toe aan de lijst
	push @{ $location->{files} },$location->{path}."/manifest.txt";
	

	#verplaats	
	my $oldpath = $location->{path};
	my $mount_conf = mount_conf();
	my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".basename($oldpath);
	say "\tmoving from $oldpath to $newpath";
	move($oldpath,$newpath);
	$location->{path} = $newpath;
	foreach my $file(@{ $location->{files} }){
		$file =~ s/^$oldpath/$newpath/;
	}
	
	#status 'registered'
	$location->{status} = "registered";
    push @{ $location->{status_history} },{
        user_name =>"-",
        status => "registered",
        datetime => time,
        comments => ""
    };
	
	locations->add($location);
	location2index($location);
	index_locations->commit();

	status2index($location);
    index_log->commit();
}

#stap 6: indexeer
say "\nindexing merge locations-projects-users\n";
locations->each(sub{
    my $location = shift;
	my $doc = location2index($location);
	say "\tlocation $location->{_id} added to index";
});
index_locations->commit();
index_locations->store->solr->optimize();

#stap 7: indexeer logs
say "\nlogging:\n";
locations()->each(sub{
    my $location = shift;
	my $doc = status2index($location);
	say "\tlocation $location->{_id} added to log (_id:$doc->{_id})" if $doc;
});
index_log->commit();
index_log->store->solr->optimize();
