#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;

my $out = Catmandu::Store::DBI->new(
    data_source => "dbi:mysql:database=imaging",
    username => "imaging",
    password => "imaging",
    bags => {
        projects => { serialization_format => "messagepack" },
        scans => { serialization_format => "messagepack" }
    }
);
my $in = Catmandu::Store::DBI->new(
    data_source => "dbi:SQLite:dbname=/tmp/imaging.db",
    bags => {
        projects => { serialization_format => "messagepack" },
        scans => { serialization_format => "messagepack" }
    }
);
my @tables = qw(projects scans);
foreach my $table(@tables){
    my $bag_in = $in->bag($table);
    my $bag_out = $out->bag($table);
    $bag_out->add_many($bag_in);
}
