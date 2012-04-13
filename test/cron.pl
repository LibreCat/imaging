#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
use lib $ENV{HOME}."/Imaging/lib";
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use File::Find;
use Try::Tiny;
use DBI;
use JSON qw(decode_json encode_json);
use XML::Simple;
use LWP::UserAgent;
use Clone qw(clone);
use DateTime;
use DateTime::Format::Strptime;

sub xml_reader {
	state $xml_reader = XML::Simple->new();
}
sub formatted_date {
	my $time = shift || time;
	DateTime::Format::Strptime::strftime(
        '%FT%TZ', DateTime->from_epoch(epoch=>$time)
    );
}
sub get_identifiers {
	my $marcxml = shift;
	$marcxml =~ s/(?:\n|\r)//go;
    my $xml = xml_reader()->XMLin($marcxml,ForceArray => 1);
    my $data_fields = [
        {
            tag => '852',
            subfield => 'j'
        }
    ];
    my $control_fields = [{
        tag => '001',
    },
    {
        tag => 003
    }];
    my %values = ();

    foreach my $control_field(@$control_fields){
        foreach my $marc_controlfield(@{ $xml->{'marc:controlfield'} }){
            if($marc_controlfield->{tag} eq $control_field->{tag}){
                $values{ $control_field->{tag} } = $marc_controlfield->{content};
                last;
            }
        }
    }
    foreach my $data_field(@$data_fields){
        foreach my $marc_datafield(@{ $xml->{'marc:datafield'} }){
            if($marc_datafield->{tag} eq $data_field->{tag}){
                foreach my $marc_subfield(@{ $marc_datafield->{'marc:subfield'} }){
                    if($marc_subfield->{code} eq $data_field->{subfield}){
                        $values{ $marc_datafield->{tag}.$marc_subfield->{code} } = $marc_subfield->{content};
                        last;
                    }
                }
                last;
            }
        }
    }
	my %identifiers = ();
    if($values{'852j'}){
		$identifiers{location} = $values{'852j'};
	}
    $identifiers{metadata} = $values{'001'};
	\%identifiers;
}


my %opts = (
    data_source => "dbi:mysql:database=imaging",
    username => "imaging",
    password => "imaging"
);
my $store = Catmandu::Store::DBI->new(%opts);
my $index = Catmandu::Store::Solr->new(
    url => "http://localhost:8983/solr/core0"
);
my $index_locations = $index->bag("locations");
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

#stap 1: zoek locations van scanners
my $sth_each = $users->prepare("select * from users where roles like '%scanner'");
my $sth_get = $users->prepare("select * from users where id = ?");
$sth_each->execute() or die($sth_each->errstr());
while(my $user = $sth_each->fetchrow_hashref()){
    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};
    open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d |" or die($!);
    while(my $dir = <CMD>){
        chomp($dir);    
        my $basename = basename($dir);
        my $location = $locations->get($basename);
		my $now = formatted_date();
        if(!$location){
            $locations->add({
                _id => $basename,
				name => undef,
                path => $dir,
                status => "incoming",
				status_history => ["incoming $now"],
                check_log => [],
                files => [],
                user_id => $user->{id},
                datetime_last_modified => time,
                comments => "",
                project_id => undef,
            });
        }
    }
    close CMD;   
}

#stap 2: doe check
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= load_package($class)->new(%$args, dir => ".");
}
my @location_ids = ();
$locations->each(sub{ push @location_ids,$_[0]->{_id} if ($_[0]->{status} && ($_[0]->{status} eq "incoming" || $_[0]->{status} eq "incoming_error")); });
foreach my $location_id(@location_ids){
    my $location = $locations->get($location_id);
    $sth_get->execute( $location->{user_id} ) or die($sth_get->errstr);
    my $user = $sth_get->fetchrow_hashref();
    if(!defined($user->{profile_id})){
        say "no profile defined for $user->{login}";
        return;
    }
    my $profile = $profiles->get($user->{profile_id});
    $location->{check_log} = [];
    my @files = ();
    foreach my $test(@{ $profile->{packages} }){
        my $ref = get_package($test->{class},$test->{args});
        $ref->dir($location->{path});        
        my($success,$errors) = $ref->test();
        push @{ $location->{check_log} }, @$errors if !$success;
        unless(scalar(@files)){
            foreach my $stats(@{ $ref->file_info() }){
                push @files,$stats->{path};
            }
        }
        if(!$success && $test->{on_error} eq "stop"){
            last;
        }
    }
    if(scalar(@{ $location->{check_log} }) > 0){
        $location->{status} = "incoming_error";
		push @{$location->{status_history}},"incoming_error ".formatted_date();
    }else{
        $location->{status} = "incoming_ok";
		push @{$location->{status_history}},"incoming_ok ".formatted_date();
        my $basename = basename($location->{path});
        my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/$basename";
        if(!move($location->{path},$newpath)){
            die($!);
        }
        foreach my $file(@files){
            $file =~ s/^$location->{path}/$newpath/;
        }
        $location->{path} = $newpath;
    }
    $location->{files} = \@files;
    $locations->add($location);
}

#stap 3: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list'
my $ua = LWP::UserAgent->new();
my $base_url = "http://adore.ugent.be/rest";

my @project_ids = ();
$projects->each(sub{ push @project_ids,$_[0]->{_id}; });

foreach my $project_id(@project_ids){

    my $project = $projects->get($project_id);
	my($total,$done) = (0,0);
    my $query = $project->{query};
    next if !$query;
	next if is_array_ref($project->{list}) && scalar(@{ $project->{list} }) > 0;

	my @list = ();

	my $res = $ua->get($base_url."?q=$query&format=json&limit=0");
	if($res->is_error()){
		die($res->content());
	}
	my $ref = decode_json($res->content);
	if($ref->{error}){
		die($ref->{error});
	}
	$total = $ref->{totalhits};
	my($offset,$limit) = (0,100);
	while($offset <= $total){
		$res = $ua->get($base_url."?q=$query&format=json&start=$offset&limit=$limit");
		if($res->is_error()){
			die($res->content());
		}
		$ref = decode_json($res->content);
		if($ref->{error}){
			die($ref->{error});
		}
		foreach my $hit(@{ $ref->{hits} }){
			my $identifiers = get_identifiers($hit->{fXML});
			if(defined($identifiers->{location})){
				push @list,$identifiers->{location};
			}else{
				push @list,$identifiers->{metadata};
			}
		}
		$offset += $limit;
	}
	$project->{list} = \@list;
	$project->{datetime_last_modified} = time;

	$projects->add($project);
};
#stap 4: ken locations toe aan projects en haal metadata op
$projects->each(sub{
	my $project = shift;
	next if !is_array_ref($project->{list});
	foreach my $location_id(@{ $project->{list} }){
		my $location_dir = $location_id;
		$location_dir =~ s/[\.\/]/-/go;
		my $location = $locations->get($location_dir);
		next if !$location;
		next if is_string($location->{metadata_id});
		my $res = $ua->get($base_url."?q=$location_id&format=json&limit=1");
		if($res->is_error()){
			die($res->content());
		}
		my $ref = decode_json($res->content);
		if($ref->{error}){
			die($ref->{error});
		}
		next if $ref->{totalhits} == 0;

		my $identifiers = get_identifiers($ref->{hits}->[0]->{fXML});
		$location->{name} = $location_id;
		$location->{metadata_id} = $identifiers->{metadata};
		$location->{marcxml} = $ref->{hits}->[0]->{fXML};
		$location->{project_id} = $project->{_id};
		$locations->add($location);
	}
});
#stap 5: indexeer
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
    $index_locations->add($doc);   
});
$index_locations->commit();
$index_locations->store->solr->optimize();
