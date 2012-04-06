#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
use lib $ENV{HOME}."/Grim/lib";
use File::Basename;
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;

my $store = Catmandu::Store::DBI->new(data_source => "dbi:SQLite:dbname=/tmp/check.db")->bag("directories");
my $conf = YAML::LoadFile("dirtest.yml");
my $test_classes = $conf->{test_classes};

my @test_packages = map {
	my $class = $_->{class};
	my $args = $_->{args} || {};
	my $ref = load_package("Grim::Test::Dir::$class")->new(dir => ".",%$args);
	$ref->{on_error} = $_->{on_error} || "continue";
	$ref;
} @$test_classes;
my $time = time;

my $topdir = shift;
exit 1 if !-d $topdir;
$topdir = File::Spec->canonpath($topdir);

my $record = { 
	_id => basename(dirname($topdir)),
	base => $topdir,
	directories => []
};
open CMD,"find $topdir -mindepth 1 -maxdepth 1 -type d |" or die($!);
while(my $dir = <CMD>){
	chomp($dir);
	say $dir;
	my $num_success = 0;
	my $directory = {
		path => $dir,
		status => "error",
		files => [],
		'logs' => []
	};
	foreach my $package(@test_packages){
		
		$package->dir($dir);
		my($success,$errors) = $package->test();
		say "\t".ref($package)." [".($success ? "success":"failed")."]";
		foreach my $error(@$errors){
			say "\t\t".$error->[0]." => ".$error->[1]." => ".$error->[2];
		}
		my $log = {
			'time' => time,
			details => {
				'package' => ref($package),
				success => $success || 0,
				errors => $errors
			}
		};
		push @{ $directory->{logs} },$log;
		if(!$success){
			if($package->{on_error} eq "stop"){
				last;
			}
		}else{
			$num_success++;
		}
	}	
	$directory->{status} = "ok" if $num_success == scalar(@test_packages);
	push @{ $record->{directories} },$directory;
}
$store->add($record);
