#!/usr/bin/env perl
use lib qw(
	/home/nicolas/Catmandu/lib
	/home/nicolas/Imaging/lib
);
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
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Array::Diff;
use File::Find;
our($a,$b);

sub formatted_date {
	my $time = shift || time;
	DateTime::Format::Strptime::strftime(
		'%FT%TZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
	);
}

my %opts = (
	data_source => "dbi:mysql:database=imaging",
	username => "imaging",
	password => "imaging"
);
my $store = Catmandu::Store::DBI->new(%opts);
my $locations = $store->bag("locations");
my $profiles = $store->bag("profiles");
my $conf_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
my $conf = YAML::LoadFile($conf_file);
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
		if(!$location){
			$locations->add({
				_id => $basename,
				name => undef,
				path => $dir,
				status => "incoming",
				status_history => [{
					user_name => $user->{login},
					status => "incoming",
					datetime => time,
					comments => ""
				}],
				check_log => [],
				files => [],
				user_id => $user->{id},
				datetime_last_modified => time,
				project_id => undef,
				metadata => [],
				comments => []
			});
		}
	}
	close CMD;   
}

#stap 2: doe check
sub get_package {
	my($class,$args)=@_;
	state $stash->{$class} ||= load_package($class)->new(%$args);
}
my @location_ids = ();

$locations->each(sub{ 

	my $location = shift;
	#nieuwe of slechte directories moeten sowieso opnieuw gecheckt worden
	if (
		$location->{status} && 
		(
			$location->{status} eq "incoming" || 
			$location->{status} eq "incoming_error" ||
			$location->{status} eq "reprocess_scans"
		)

	){
		push @location_ids,$location->{_id};
	}
	#incoming_ok enkel indien er iets aan bestandslijst gewijzigd is
	elsif($location->{status} eq "incoming_ok"){
		my $new = [];
		find({			
			wanted => sub{
			my $path = abs_path($File::Find::name);
			return if $path eq abs_path($location->{path});
			push @$new,$path;
			},
			no_chdir => 1
			},$location->{path});
		my $old = $location->{files} || [];

		my $diff = Array::Diff->diff($old,$new);
		if( $diff->count != 0 ){	
			say STDERR "something has changed to $location->{path}, lets check what it is";
			push @location_ids,$location->{_id};
		}
	}

});

#test timing
use Time::HiRes;
my $timing = {};
my $num_checked = 0;
my $totalsum = 0;

foreach my $location_id(@location_ids){
	my $location = $locations->get($location_id);

	#directory is ondertussen riebedebie
	if(!(-d $location->{path})){
		say "$location->{path} is gone, deleting from database";
		$locations->delete($location->{_id});
		next;
	}

	say "checking $location_id at $location->{path}";
	$sth_get->execute( $location->{user_id} ) or die($sth_get->errstr);
	my $user = $sth_get->fetchrow_hashref();
	if(!defined($user->{profile_id})){
		say STDERR "no profile defined for $user->{login}";
		next;
	}
	my $profile = $profiles->get($user->{profile_id});
	if(!$profile){
		say STDERR "strange, profile_id is defined in table users, but no profile could be fetched from table profiles";
		next;
	}

	#test timing
	$num_checked++;

	$location->{check_log} = [];
	my @files = ();
	foreach my $test(@{ $profile->{packages} }){

		$timing->{$test->{class}} ||= [];
		my $time_start = Time::HiRes::time;

		my $ref = get_package($test->{class},$test->{args});
		$ref->dir($location->{path});        
		my($success,$errors) = $ref->test();

		#test timing
		my $time_end = Time::HiRes::time;
		push @{ $timing->{$test->{class}} } , $time_end - $time_start;
		$totalsum += $time_end - $time_start;

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
		$location->{status_history}->[1] = {
			user_name =>"-",
			status => "incoming_error",
			datetime => time,
			comments => ""
		};
	}else{
		$location->{status} = "incoming_ok";
		$location->{status_history}->[1] = {
			user_name =>"-",
			status => "incoming_ok",
			datetime => time,
			comments => ""
		};
		#verplaats maar pas 's nachts!
	}

	$location->{files} = \@files;
	$locations->add($location);
}

#test timing
say "timing reports:";
use List::Util qw(reduce);
use Time::Seconds;
foreach my $timing_key(sort keys %$timing){
	my $times = $timing->{$timing_key};
	my $sum = reduce { $a + $b } @{ $timing->{$timing_key} };
	my $average = $sum / scalar(@{ $timing->{$timing_key} });
	say "$timing_key => ".Time::Seconds->new($average)->pretty;
}
say "\ntotal average per directory:".Time::Seconds->new($totalsum / $num_checked);
