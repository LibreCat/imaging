#!/usr/bin/env perl
use Catmandu::Sane;
use JSON qw(decode_json encode_json);
use XML::Simple;
use LWP::UserAgent;
use Data::Dumper;


my $ua = LWP::UserAgent->new();
my $query = shift || "*";
my $base_url = "http://adore.ugent.be/rest";

my $res = $ua->get($base_url."?q=$query&format=json&limit=0");
if($res->is_error()){
    die($res->content());
}
my $ref = decode_json($res->content);
if($ref->{error}){
    die($ref->{error});
}
my $total = $ref->{totalhits};
my($offset,$limit) = (0,100);
my $xml_reader = XML::Simple->new();
while(($offset + $limit - 1) <= $total){
    $res = $ua->get($base_url."?q=$query&format=json&start=$offset&limit=$limit");
    if($res->is_error()){
        die($res->content());
    }
    $ref = decode_json($res->content);
    if($ref->{error}){
        die($ref->{error});
    }
    foreach my $hit(@{ $ref->{hits} }){
        my $xml = $xml_reader->XMLin($hit->{fXML},ForceArray => 1);
        foreach my $marc_datafield(@{ $xml->{'marc:datafield'} }){
            if($marc_datafield->{tag} eq "852"){
                foreach my $marc_subfield(@{ $marc_datafield->{'marc:subfield'} }){
                    if($marc_subfield->{code} eq "j"){
                        my $location = $marc_subfield->{content};
                        $location =~ s/[\.\/]/-/go;
                        say $marc_subfield->{content}." => $location";
                        last;
                    }
                }
                last;
            }
        }
    }

    $offset += $limit;
}
