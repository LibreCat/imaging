#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
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

sub formatted_date {
	my $time = shift || time;
	DateTime::Format::Strptime::strftime(
        '%FT%TZ', DateTime->from_epoch(epoch=>$time)
    );
}
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
				push @list,$hit->{fSYS};
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

#stap 2: ken locations toe aan projects en haal metadata op
$projects->each(sub{
	my $project = shift;
	next if !is_array_ref($project->{list});
	foreach my $location_id(@{ $project->{list} }){
		my $location_dir = $location_id;
		$location_dir =~ s/[\.\/]/-/go;
		my $location = $locations->get($location_dir);

		#directory nog niet aanwezig
		next if !$location;

		#indexeer pas wanneer de directory ok is
		my $status = $location->{status};
		next if $status eq "incoming" || $status eq "incoming_error";

		#deze directory is reeds geregistreerd
		next if is_string($location->{metadata});

		$location->{name} = $location_id;
		$location->{project_id} = $project->{_id};
		$locations->add($location);


		#haal metadata op -> status = metadata_ok pas ok indien juist één element in metadata!
#		my $res = $meercat->search($location_id,{rows=>1000});
#		next if $res->content->{response}->{numFound} == 0;
#
#		my $docs = $res->content->{response}->{docs};

#automatische koppeling -> voor later!
#		$location->{metadata} = [];
#		foreach my $doc(@$docs){
#			push @{ $location->{metadata} },{
#				fSYS => $doc->{fSYS},
#				fXML => $doc->{fXML}
#			};
#		}
	}
});

#stap 3: indexeer
$locations->each(sub{
    my $location = shift;
    my $doc = clone($location);
	delete $doc->{marcxml};
	
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
	$doc->{datetime_last_modified} = formatted_date( $doc->{datetime_last_modified} );
        
    say $doc->{_id};
    $own_index->add($doc);   
});
$own_index->commit();
$own_index->store->solr->optimize();
