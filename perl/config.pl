#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is);
use File::Basename qw();
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;

BEGIN {
    my $appdir = Cwd::realpath("..");
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}
use Dancer::Plugin::Imaging::Routes::Utils;
use Data::Dumper;
print Dumper(core());
