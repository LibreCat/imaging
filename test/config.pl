#!/usr/bin/env perl
use Catmandu::Sane;
use Dancer qw(:script);
use File::Spec;
use Cwd;
use open qw(:std :utf8);
use Catmandu;

my $appdir = Cwd::realpath("..");
Dancer::Config::setting(appdir => $appdir);
Dancer::Config::setting(public => "$appdir/public");
Dancer::Config::setting(confdir => $appdir);
Dancer::Config::setting(envdir => "$appdir/environments");
Dancer::Config::load();
Catmandu->load($appdir);

print to_json(Catmandu->config);
