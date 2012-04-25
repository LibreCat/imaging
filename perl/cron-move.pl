#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use File::Copy qw(copy move);
use File::Path qw(mkpath);
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use Try::Tiny;
use DBI;

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
sub locations {
	state $locations = store()->bag("locations");
}

my $locations = locations();

my @ids_to_be_moved = ();

$locations->each(sub{
	my $location = shift;
	if(
		$location->{status} eq "reprocess_scans" && 
		$location->{busy} && $location->{busy_reason} eq "move"
		&& is_string($location->{newpath})
	){
		push @ids_to_be_moved,$location->{_id};
	}
});
foreach my $id(@ids_to_be_moved){
	say $id;
	my $location = $locations->get($id);
	
	my $newpath = $location->{newpath};
	my $oldpath = $location->{path};

	mkpath($newpath);
    if(move($oldpath,$newpath)){
    	say "\tmoved from $oldpath to $newpath";
		$location->{path} = $newpath;
		foreach my $file(@{ $location->{files} }){
			$file =~ s/^$oldpath/$newpath/;
		}

		my @deletes = qw(busy busy_reason newpath);
		delete $location->{$_} foreach(@deletes);

		$locations->add($location);	
	}else{
		say STDERR "unable to move $oldpath to $newpath:$!";
	}
}
