#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use File::Basename;
use Cwd qw(abs_path);
use File::Spec;
use YAML;
use Try::Tiny;
use WebService::Solr;
use XML::Simple;
use Data::Dumper;

#variabelen
sub xml_simple {
    state $xml_simple = XML::Simple->new();
}
sub config {
    state $config = do {
        my $config_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
        YAML::LoadFile($config_file);
    };
}
sub meercat {
    state $meercat = WebService::Solr->new(
        config->{'index'}->{meercat}->{url},
        {default_params => {wt => 'json'}}
    );
}
sub str_clean {
    my $str = shift;
    $str =~ s/\n//gom;
    $str =~ s/^\s+//go;
    $str =~ s/\s+$//go;
    $str =~ s/\s\s+/ /go;
    $str;
}
sub marcxml_flatten {
    my $ref = shift;
    my @text = ();
    foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
        foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
            next if !is_string($marc_subfield->{content});
            push @text,$marc_subfield->{content};
        }
    }
    foreach my $control_field(@{ $ref->{'marc:controlfield'} }){
        next if !is_string($control_field->{content});
        push @text,$control_field->{content};
    }
    return \@text;
}

my $query = shift;
$query || die("usage: $0 <query>\n");

my $meercat = meercat();
my $res = $meercat->search($query,{rows=>0});
my $total = $res->content->{response}->{numFound};

my($offset,$limit) = (0,1000);
while($offset <= $total){
    $res = $meercat->search($query,{start => $offset,rows => $limit});
    my $hits = $res->content->{response}->{docs};

    foreach my $hit(@$hits){
        say $hit->{fSYS};
        my $ref = xml_simple->XMLin($hit->{fXML},ForceArray => 1);
        my $doc = marcxml_flatten($ref);
        print Dumper($doc);
    }
    $offset += $limit;
}
