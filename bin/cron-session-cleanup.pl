#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu::Util qw(:is);
use Catmandu::Sane;
use DBI;
use Imaging qw(local_time);
use Imaging::Util qw(:lock);

my($pidfile);
INIT {
	#voer niet uit wanneer andere instantie draait!
	$pidfile = "/tmp/imaging-session-cleanup.pid";
  acquire_lock($pidfile);
}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}

my $session_options = config->{session_options};

my $dbh = DBI->connect(
  $session_options->{dsn}, 
  $session_options->{user},
  $session_options->{password},
  { RaiseError => 1,AutoCommit => 1 }
) or die($DBI::errstr);

my $sql_delete_old_sessions = $session_options->{sql_delete_old_sessions};
is_string($sql_delete_old_sessions) or die("no sql statement set for deleting old sessions");

my $none = '0E0';
my $num_deleted = $dbh->do($sql_delete_old_sessions) or die($dbh->errstr);
say "number of sessions deleted at ".local_time()." : ".(is_string($num_deleted) && $num_deleted ne $none ? $num_deleted : 0);

$dbh->disconnect if $dbh;
