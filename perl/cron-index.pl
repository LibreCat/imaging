#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use YAML;
use Try::Tiny;
use DBI;
use Clone qw(clone);
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use WebService::Solr;
use Digest::MD5 qw(md5_hex);
use Catmandu::Importer::MARC;
use Catmandu::Fix;
use Time::HiRes;
use XML::Simple;

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
sub projects {
    state $projects = store()->bag("projects");
}
sub locations {
    state $locations = store()->bag("locations");
}
sub meercat {
    state $meercat = WebService::Solr->new(
        config->{'index'}->{meercat}->{url},
        {default_params => {wt => 'json'}}
    );
}
sub index_locations {
    state $index_locations = Catmandu::Store::Solr->new(
        %{ config->{store}->{'index'}->{options} }
    )->bag();
}
sub users {
    state $users = do {
        my $opts = store_opts();
        DBI->connect($opts->{data_source}, $opts->{username}, $opts->{password}, {
            AutoCommit => 1,
            RaiseError => 1,
            mysql_auto_reconnect => 1
        });
    };
}
sub users_each {
    state $users_each = users->prepare("select * from users where roles like '%scanner'");
}
sub users_get {
    state $users_get = users->prepare("select * from users where id = ?");
}

sub formatted_date {
    my $time = shift || Time::HiRes::time;
    DateTime::Format::Strptime::strftime(
        '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}
sub marcxml_flatten {
    my $xml = shift;
    my $ref = xml_simple->XMLin($xml,,ForceArray => 1);
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
sub location2index {
    my $location = shift;       

    my $doc = clone($location);
    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $location->{metadata} }); 
    
    $doc->{text} = [];
    push @{ $doc->{text} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$location->{metadata}});

    my @deletes = qw(metadata comments busy busy_reason);
    delete $doc->{$_} foreach(@deletes);
    $doc->{metadata_id} = \@metadata_ids;

    $doc->{files} = [ map { $_->{path} } @{ $location->{files} || [] } ];

    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_name}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    my $project;
    if($location->{project_id} && ($project = projects()->get($location->{project_id}))){
        foreach my $key(keys %$project){
            next if $key eq "list";
            my $subkey = "project_$key";
            $subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }

    if($location->{user_id}){
        my $users_get = users_get();
        $users_get->execute( $location->{user_id} ) or die($users_get->errstr);
        my $user = $users_get->fetchrow_hashref();
        if($user){
            $doc->{user_name} = $user->{name};
            $doc->{user_login} = $user->{login};
            $doc->{user_roles} = [split(',',$user->{roles})];
        }
    }

    foreach my $key(keys %$doc){
        next if $key !~ /datetime/o;
        $doc->{$key} = formatted_date($doc->{$key});
    }
    index_locations()->add($doc);
    $doc;
}

locations->each(sub{
    my $location = shift;
    my $doc = location2index($location);
    say "\tlocation $location->{_id} added to index";
});
index_locations->commit();
index_locations->store->solr->optimize();
