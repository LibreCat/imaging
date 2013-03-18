#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu qw(store);
use Dancer::Plugin::Database;
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use File::Basename qw();
use Cwd qw(abs_path);

BEGIN {
  #load configuration
  my $appdir = Cwd::realpath(
      dirname(dirname(
          Cwd::realpath( __FILE__)
      ))
  );
  Dancer::Config::setting(appdir => $appdir);
  Dancer::Config::setting(public => "$appdir/public");
  Dancer::Config::setting(confdir => $appdir);
  Dancer::Config::setting(envdir => "$appdir/environments");
  Dancer::Config::load();
  Catmandu->load($appdir);
}

my @users = database->quick_select("users",{});
my $bag = store("core")->bag('users2');
use Data::Dumper;
foreach my $user(@users){
  $user->{_id} = $user->{login};
  delete $user->{id};
  $user->{roles} = [ map { $_ =~ s/^\s+|\s+$//; $_  } split /\,/, $user->{roles} ];
  $bag->add($user);
}
