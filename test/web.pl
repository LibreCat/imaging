#!/usr/bin/env perl
use Catmandu::Sane;
use WebService::Solr;
use JSON;
use open qw(:utf8 :std);
use Data::Util qw(:check);

my $solr = WebService::Solr->new(
	"http://localhost:4000/solr",{default_params => {wt => 'json'}}
);
my $query = shift || "*:*";
my $res = $solr->search($query,{rows=>10000});

my $num = $res->content->{response}->{numFound};
my $docs = $res->content->{response}->{docs};
foreach my $doc(@$docs){
	if(is_array_ref($doc->{location})){
		say $_ foreach(@{ $doc->{location} });
	}
}
