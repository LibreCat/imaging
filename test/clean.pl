#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(store);
use JSON qw(encode_json);

Catmandu->load("/home/nicolas/Imaging");

my @list = ();
my $scans = store("core")->bag("scans");
$scans->each(sub{
    push @list,$_[0]->{_id};
});
for my $id(@list){
    my $scan = $scans->get($id);
    delete $scan->{$_} for(qw(newpath temp_user));
    say $id;
    for my $key(sort keys %$scan){
        next if $key eq "_id";
        say sprintf(" %30s : %s",$key,$scan->{$key} || "");
    }
    $scans->add($scan);
}
