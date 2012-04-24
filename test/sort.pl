#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;


#variabelen
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
my $result = index_log->search(
	query => "*",
	'sort' => ['datetime desc','location_id desc']
);
foreach my $hit(@{ $result->hits }){
	say sprintf('%30s %s',$hit->{location_id},$hit->{datetime});	
}
