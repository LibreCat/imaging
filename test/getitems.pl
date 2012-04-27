#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use open qw(:std :utf8);
use Try::Tiny;
use XML::Simple;
use Data::Dumper;

our($a,$b);

sub meercat {
	state $meercat = WebService::Solr->new(
        "http://localhost:4000/solr",{default_params => {wt => 'json'}}
    );
}
sub xml_simple {
	state $xml_simple = XML::Simple->new();
}
foreach my $query(@ARGV){

	my @list = ();

	my $meercat = meercat();
	my $res = $meercat->search($query,{rows=>0});
	my $total = $res->content->{response}->{numFound};

	my($offset,$limit) = (0,1000);
	while($offset <= $total){
		$res = $meercat->search($query,{start => $offset,rows => $limit});
		my $hits = $res->content->{response}->{docs};

		foreach my $hit(@$hits){
			my $ref = xml_simple->XMLin($hit->{fXML},ForceArray => 1);

			#zoek items in Z30 3, en nummering in Z30 h
			my @items = ();

			foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
				if($marc_datafield->{tag} eq "Z30"){
					my $item = { 
						source => $hit->{source},
						fSYS => $hit->{fSYS}
					};
					foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
						if($marc_subfield->{code} eq "3"){
							$item->{"location"} = $marc_subfield->{content};
						}
						if($marc_subfield->{code} eq "h" && $marc_subfield->{content} =~ /^V\.\s+(\d+)$/o){
							$item->{"number"} = $1;
                        }
					}
					push @items,$item;					
				}
			}
			push @list,@items;
		}
		$offset += $limit;
	}
	print Dumper(\@list);
};
