#!/usr/bin/env perl
use Dancer;
use Plack::Builder;
use Plack::Util;

#laad configuratie van catmandu één keer!
use Catmandu qw(:load);

#routes
use all qw(
	Imaging::Routes::*
);
#default-route: MUST BE LAST IN ROW!
use Imaging::Route;

my $app = sub {
	my $env = shift;
	my $request = Dancer::Request->new(env=>$env);
	Dancer->dance($request);
};
builder {
	$app;
};
