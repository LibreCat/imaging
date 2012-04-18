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
use Digest::MD5;

#functions
	sub formatted_date {
		my $time = shift || time;
		DateTime::Format::Strptime::strftime(
			'%FT%TZ', DateTime->from_epoch(epoch=>$time)
		);
	}

#important variables
	my %opts = (
		data_source => "dbi:mysql:database=imaging",
		username => "imaging",
		password => "imaging"
	);
	my $store = Catmandu::Store::DBI->new(%opts);
	#meercat-index -> doe enkele select!!
	my $meercat = WebService::Solr->new(
		"http://localhost:4000/solr",{default_params => {wt => 'json'}}
	);
	#eigen index -> bedoelt om te updaten !!
	my $own_index = Catmandu::Store::Solr->new(
		url => "http://localhost:8983/solr/core0"
	)->bag("locations");
	my $projects = $store->bag("projects");
	my $locations = $store->bag("locations");
	my $profiles = $store->bag("profiles");
	my $conf = YAML::LoadFile("../environments/development.yml");
	my $mount_conf = $conf->{mounts}->{directories};

	my $users = DBI->connect($opts{data_source}, $opts{username}, $opts{password}, {
		AutoCommit => 1,
		RaiseError => 1,
		mysql_auto_reconnect => 1
	});
	my $sth_each = $users->prepare("select * from users where roles like '%scanner'");
	my $sth_get = $users->prepare("select * from users where id = ?");

#stap 1: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list'
my @project_ids = ();
$projects->each(sub{ push @project_ids,$_[0]->{_id}; });

foreach my $project_id(@project_ids){

    my $project = $projects->get($project_id);
	my($total,$done) = (0,0);
    my $query = $project->{query};
    next if !$query;
	next if is_array_ref($project->{list}) && scalar(@{ $project->{list} }) > 0;

	my @list = ();

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
				push @list,$hit->{source}.":".$hit->{fSYS};
			}
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

	$projects->add($project);
};

#stap 2: ken locations toe aan projects
$projects->each(sub{
	my $project = shift;
	say $project->{query};
	return if !is_array_ref($project->{list});
	foreach my $location_id(@{ $project->{list} }){
		my $location_dir = $location_id;
		if($location_dir =~ /^rug01:\d{9}$/o){
			$location_dir =~ s/rug01:/RUG01-/go;
		}else{
			$location_dir =~ s/[\.\/]/-/go;	
		}
		my $location = $locations->get($location_dir);

		#directory nog niet aanwezig
		next if !$location;
		#enkel incoming_ok
		my $status = $location->{status};

        next if $status eq "incoming" || $status eq "incoming_error";

        #location toekennen aan project
		if(!$location->{project_id}){
			$location->{name} = $location_id;
	        $location->{project_id} = $project->{_id};
		}

		#haal metadata op
		if(!(
			is_array_ref($location->{metadata}) && scalar(@{ $location->{metadata} }) > 0
		)){
			my $res = $meercat->search($location_id,{rows=>1000});
			if($res->content->{response}->{numFound} > 0){			

				my $docs = $res->content->{response}->{docs};

				$location->{metadata} = [];
				foreach my $doc(@$docs){
					push @{ $location->{metadata} },{
						fSYS => $doc->{fSYS},#000000001
						source => $doc->{source},#rug01
						fXML => $doc->{fXML}
					};
				}

			}
		}

		$locations->add($location);

	}
});
#stap 3: registreer locations die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
$locations->each(sub{
	my $location = shift;
	push @incoming_ok,$location->{_id} if $location->{status} eq "incoming_ok";
});

foreach my $id (@incoming_ok){
	my $location = $locations->get($id);

	#registreer
	$location->{status} = "registered";
	
	push @{ $location->{status_history} },"admin registered ".formatted_date();

	#verplaats	
	my $oldpath = $location->{path};
	my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".basename($oldpath);
	say "moving from $oldpath to $newpath";
	move($oldpath,$newpath);
	$location->{path} = $newpath;
	foreach my $file(@{ $location->{files} }){
		$file =~ s/^$oldpath/$newpath/;
	}
	
	#pas manifest aan
		
	#verwijder oude manifest
	unlink("$newpath/manifest.txt") if -f "$newpath/manifest.txt";
	my $index = first_index { $_ eq "$newpath/manifest.txt" } @{ $location->{files} };
	if($index >= 0){
		splice(@{ $location->{files} },$index,1);
	}

	#maak nieuwe manifest
	local(*MANIFEST);
	open MANIFEST,">$newpath/manifest.txt" or die($!);
	foreach my $file(@{ $location->{files} }){
		local(*FILE);
		open FILE,$file or die($!);
		my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
		say MANIFEST "$md5sum_file ".basename($file);
		close FILE;
	}
	close MANIFEST;

	#voeg manifest toe aan de lijst
	push @{ $location->{files} },"$newpath/manifest.txt";
	
	$locations->add($location);
}
#stap 4: indexeer
$locations->each(sub{
    my $location = shift;
	return if $location->{status} eq "incoming" || $location->{status} eq "incoming_error" || $location->{status} eq "incoming_ok";
    my $doc = clone($location);
	delete $doc->{metadata};
	
    my $project;
    if($location->{project_id} && ($project = $projects->get($location->{project_id}))){
        foreach my $key(keys %$project){
			next if $key eq "list";
            my $subkey = "project_$key";
			$subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }
    if($location->{user_id}){
        $sth_get->execute( $location->{user_id} ) or die($sth_get->errstr);
        my $user = $sth_get->fetchrow_hashref();
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
        
    $own_index->add($doc);   
});
$own_index->commit();
$own_index->store->solr->optimize();

#stap 5: gooi records met incoming en incoming_error weg
#reden: indien een mapnaam verbetert is, dan blijft het oude record staan (zelfs niet meer in /ready/$login te zien), en wordt daar niet meer naar gekeken
my @bad_locations = ();
$locations->each(sub{
	my $location = shift;
	push @bad_locations,$location->{_id} if $location->{status} eq "incoming" || $location->{status} eq "incoming_error";
});
foreach my $id(@bad_locations){
	say "deleting bad location $id from database";
	$locations->delete($id);
}
