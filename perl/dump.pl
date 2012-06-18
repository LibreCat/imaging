#!/usr/bin/env perl
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu;
use File::Basename qw();
use File::Path;
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use open qw(:std :utf8);

BEGIN {
    my $appdir = Cwd::realpath(
        dirname(dirname(
            Cwd::realpath(__FILE__)
        ))
    );
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}
use Dancer::Plugin::Imaging::Routes::Utils;
my $scans = scans;
my $id = shift;
if($id){
    my $obj = scans->get($id);
    print to_json($obj,{ pretty => 1 }) if $obj;
}
