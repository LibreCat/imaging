#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
use lib $ENV{HOME}."/Imaging/lib";
use File::Basename;
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use File::Find;
use Try::Tiny;

my $store = Catmandu::Store::DBI->new(
	data_source => "dbi:mysql:database=imaging",
	username => "imaging",
	password => "imaging"
)->bag("directory_ready");
my $conf = YAML::LoadFile("dirtest.yml");
my $test_classes = $conf->{test_classes};

my @test_packages = map {
	my $class = $_->{class};
	my $args = $_->{args} || {};
	my $ref = load_package("Imaging::Test::Dir::$class")->new(dir => ".",%$args);
	$ref->{on_error} = $_->{on_error} || "continue";
	$ref;
} @$test_classes;
my $time = time;

$store->each(sub{
	my $record = shift;
	my $topdir = $record->{base};
	say $topdir;

	my $c = "find $topdir -mindepth 1 -maxdepth 1 -type d";
	open CMD,"$c |" or die($!);
	while(my $dir = <CMD>){
		chomp($dir);
		say "\t$dir";
		my $num_success = 0;
		my $directory = {
			path => $dir,
			status => "error",
			files => [],
			'logs' => []
		};
		my @files = ();	
		find({
			wanted => sub{
				return if abs_path($_) eq abs_path($dir);
				push @files,abs_path($File::Find::name);
			},
			no_chdir => 1
		},$dir);
		$directory->{files} = \@files;
		foreach my $package(@test_packages){
			$package->dir($dir);
			my($success,$errors) = $package->test();	

			say "\t\t".ref($package)." [".($success ? "success":"failed")."]";
			foreach my $error(@$errors){
				say "\t\t\t".$error->[0]." => ".$error->[1]." => ".$error->[2];
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
	close CMD;
	#use JSON;
	#print JSON->new->utf8(1)->pretty(1)->encode($record);
	$store->add($record);
});
