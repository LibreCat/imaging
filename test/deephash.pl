#!/usr/bin/env perl
use Catmandu::Sane;
use Dancer qw(:script);
use Catmandu qw(store);
use Imaging::Util qw(data_at);
use Data::Dumper;

BEGIN {
    my $appdir = Cwd::realpath("..");
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}

my $config = config;
print Dumper(data_at($config,"mounts.directories.directories.ready.warn_after"));
