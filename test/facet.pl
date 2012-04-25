#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::Solr;
use Try::Tiny;
use Data::Dumper;

#variabelen
sub index_locations {
	state $index_locations = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core0"
    )->bag("locations");
}

my $solr = index_locations->store->solr;
try{
	my $res = $solr->search("* AND _bag:locations",{ rows => 0,facet => "true","facet.field"=>"status" });
	my $facet_counts = $res->facet_counts;
	print Dumper($facet_counts);
};
