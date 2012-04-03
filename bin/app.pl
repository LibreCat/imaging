#!/usr/bin/env perl
use Dancer;
use Plack::Builder;
use Plack::Session::Store::Cache;
use Plack::Util;

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
	enable 'Session',
		store => Plack::Session::Store::Cache->new(
		cache => Plack::Util::load_class(config->{cache}->{session}->{package})->new(
		    %{ config->{cache}->{session}->{options} }
		)
	);
	$app;
};
