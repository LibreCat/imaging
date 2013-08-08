#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu::Sane;
use Catmandu::Util qw(read_file);
use File::Basename;
use Cwd qw(abs_path);
use DBI;

my $session_options = config->{session_options};

my $dbh = DBI->connect(
  $session_options->{dsn}, 
  $session_options->{user},
  $session_options->{password},
  { RaiseError => 1,AutoCommit => 1 }
) or die($DBI::errstr);

my $dir = dirname(dirname(abs_path(__FILE__)))."/install";

for my $dbi_source(<"$dir/*.tab">){

  my $sql = read_file($dbi_source);
  say $sql;
  $dbh->do($sql) or die($dbh->errstr);

}

$dbh->disconnect if $dbh;
