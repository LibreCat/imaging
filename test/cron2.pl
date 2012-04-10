#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils;
use lib $ENV{HOME}."/Imaging/lib";
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use File::Find;
use Try::Tiny;
use DBI;
use JSON qw(decode_json encode_json);
use XML::Simple;
use LWP::UserAgent;
use Clone qw(clone);

my %opts = (
    data_source => "dbi:mysql:database=imaging",
    username => "imaging",
    password => "imaging"
);
my $store = Catmandu::Store::DBI->new(%opts);
my $index = Catmandu::Store::Solr->new(
    url => "http://localhost:8983/solr/core0"
);
my $index_locations = $index->bag("locations");
my $projects = $store->bag("projects");
my $locations = $store->bag("locations");
my $profiles = $store->bag("profiles");
my $conf = YAML::LoadFile("../environments/development.yml");
my $mount_conf = $conf->{mounts}->{directories};

my $users = DBI->connect($opts{data_source}, $opts{username}, $opts{password}, {
    AutoCommit => 1,
    RaiseError => 1,
    mysql_auto_reconnect => 1
});

#stap 1: zoek locations van scanners
my $sth_each = $users->prepare("select * from users where roles like '%scanner'");
my $sth_get = $users->prepare("select * from users where id = ?");
$sth_each->execute() or die($sth_each->errstr());
while(my $user = $sth_each->fetchrow_hashref()){
    my $ready = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};
    open CMD,"find $ready -mindepth 1 -maxdepth 1 -type d |" or die($!);
    while(my $dir = <CMD>){
        chomp($dir);    
        my $basename = basename($dir);
        my $location = $locations->get($basename);
        if(!$location){
            $locations->add({
                _id => $basename,
                stadium => "ready",
                path => $dir,
                status => "error",
                log => [],
                files => [],
                user_id => $user->{id},
                datetime_last_modified => time,
                comments => "",
                project_id => undef
            });
        }
    }
    close CMD;   
}

#stap 2: doe check
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= load_package($class)->new(%$args, dir => ".");
}
my @location_ids = ();
$locations->each(sub{ push @location_ids,$_[0]->{_id} if $_[0]->{stadium} eq "ready"; });
foreach my $location_id(@location_ids){
    my $location = $locations->get($location_id);
    $sth_get->execute( $location->{user_id} ) or die($sth_get->errstr);
    my $user = $sth_get->fetchrow_hashref();
    if(!defined($user->{profile_id})){
        say "no profile defined for $user->{login}";
        return;
    }
    my $profile = $profiles->get($user->{profile_id});
    $location->{log} = [];
    my @files = ();
    foreach my $test(@{ $profile->{packages} }){
        my $ref = get_package($test->{class},$test->{args});
        $ref->dir($location->{path});        
        my($success,$errors) = $ref->test();
        push @{ $location->{log} }, @$errors if !$success;
        unless(scalar(@files)){
            foreach my $stats(@{ $ref->file_info() }){
                push @files,$stats->{path};
            }
        }
        if(!$success && $test->{on_error} eq "stop"){
            last;
        }
    }
    if(scalar(@{ $location->{log} }) > 0){
        $location->{status} = "error";
    }else{
        $location->{status} = "ok";
        my $basename = basename($location->{path});
        my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/$basename";
        if(!move($location->{path},$newpath)){
            die($!);
        }
        foreach my $file(@files){
            $file =~ s/^$location->{path}/$newpath/;
        }
        $location->{path} = $newpath;
        $location->{stadium} = "processed";
    }
    $location->{files} = \@files;
    $locations->add($location);
}

#stap 3: ken locations toe aan projecten -> TODO
my $ua = LWP::UserAgent->new();
my $base_url = "http://adore.ugent.be/rest";

$projects->each(sub{

    my $project = shift;
    my $query = $project->{query};
    next if !$query;

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
                            my $location_id = $marc_subfield->{content};
                            $location_id =~ s/[\.\/]/-/go;
                            say $marc_subfield->{content}." => $location_id";
                            my $location = $locations->get($location_id);
                            if($location){
                                $location->{project_id} = $project->{_id};
                                $locations->add($location);
                            }
                            last;
                        }
                    }
                    last;
                }
            }
        }
        $offset += $limit;
    }
});
#stap 4: vroegere locations die op 'processed' stonden -> nog niet verplaatst naar 'reprocessing'?
# => TODO: ene keer naar 'reprocessing', andere keer naar elders? (of verdwenen?)
#stap 5: indexeer
$locations->each(sub{
    my $location = shift;
    my $doc = clone($location);
    my $project;
    if($location->{project_id} && ($project = $locations->get($location->{project_id}))){
        foreach my $key(keys %$project){
            my $subkey = "project_$key";
            $doc->{$subkey} = $project->{$key} if $project->{$key};
        }
    }
    if($location->{user_id}){
        $sth_get->execute( $location->{user_id} ) or die($sth_get->errstr);
        my $user = $sth_get->fetchrow_hashref();
        if($user){
            $doc->{user_name} = $user->{name};
            $doc->{user_login} = $user->{login};
            $doc->{user_roles} = [split(',',$user->{roles})];   
        }
    }
    my $date = DateTime->from_epoch(epoch=>$doc->{datetime_last_modified});
    $doc->{datetime_last_modified} = DateTime::Format::Strptime::strftime(
        '%FT%TZ',$date
    );
        
    say $doc->{_id};
    $index_locations->add($doc);   
});
$index_locations->commit();
$index_locations->store->solr->optimize();
