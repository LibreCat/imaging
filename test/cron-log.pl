#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use open qw(:std :utf8);
use DateTime;
use DateTime::Format::Strptime;
use Clone qw(clone);
use Digest::MD5 qw(md5_hex);

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
	my $locations = $store->bag("locations");

	#eigen index -> bedoelt om te updaten !!
	my $own_index = Catmandu::Store::Solr->new(
		url => "http://localhost:8983/solr/core1"
	)->bag("log_locations");


#stap 1: indexeer logs indien status 'registered' of hoger
$locations->each(sub{
    my $location = shift;
	return if $location->{status} eq "incoming" || $location->{status} eq "incoming_error" || $location->{status} eq "incoming_ok";
	
	foreach my $history(@{ $location->{status_history} || [] }){
		my $doc = clone($history);
		$doc->{datetime} = formatted_date($doc->{datetime});
		$doc->{location_id} = $location->{_id};
		my $blob = join('',map { $doc->{$_} } sort keys %$doc);
		$doc->{_id} = md5_hex($blob);
		$own_index->add($doc);   
	}
});
$own_index->commit();
$own_index->store->solr->optimize();
