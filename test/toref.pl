#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use Cwd qw(abs_path);
use File::Spec;
use YAML;
use XML::Simple;
use JSON;
use Hash::Flatten;

sub flatten_all {
    my $hash = shift;
    $hash = Hash::Flatten::flatten($hash);
    [values %$hash];
}

#variabelen
sub xml_simple {
state $xml_simple = XML::Simple->new();
}
sub from_xml {
xml_simple->XMLin($_[0],ForceArray => 1);
}
sub config {
state $config = do {
    my $config_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
    YAML::LoadFile($config_file);
};
}
sub store_opts {
state $opts = do {
    my $config = config;
    my %opts = (
        data_source => $config->{store}->{core}->{options}->{data_source},
        username => $config->{store}->{core}->{options}->{username},
        password => $config->{store}->{core}->{options}->{password}
    );
    \%opts;
};
}
sub store {
state $store = Catmandu::Store::DBI->new(%{ store_opts() });
}
sub scans {
state $scans = store()->bag("scans");
}
sub marcxml_flatten {
my $xml = shift;
my $ref = xml_simple->XMLin($xml,ForceArray => 1);
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

scans()->each(sub{
    my $scan = shift;
    my $xml = $scan->{metadata}->[0]->{fXML};
    return unless($xml);
    $xml =~ s/(?:\n|\t)//go;
    $xml =~ s/\s\s+/ /go;
    print JSON::to_json(
        flatten_all(from_xml($xml))
    );
#    print JSON::to_json(
#        marcxml_flatten($xml)
#    );   
});
