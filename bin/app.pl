#!/usr/bin/env perl
use Dancer;
use Plack::Builder;

#laad configuratie van catmandu één keer!
use Catmandu qw(:load);

#things that must happen first
use Imaging::Routes::Control::First;

#routes
use all qw(Imaging::Routes::*);

#things that must happen last
use Imaging::Routes::Control::Last;

my $app = sub {
	my $env = shift;
	my $request = Dancer::Request->new(env=>$env);
	Dancer->dance($request);
};
builder {
  $app;
};
