#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename;
use File::Find;
use DateTime::Format::Strptime;
use DateTime;
use Cwd qw(abs_path);
use Getopt::Long;

sub sort_mtime {
  my @files = @_;
  @files = sort { 
    (lstat($a))[9] <=> (lstat($b))[9];
  }@files;
  @files;
}

sub local_date {
  my $time = shift || time;
  $time = int($time);
  DateTime::Format::Strptime::strftime(
    '%F', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
  );
}
sub usage {
  say STDERR "usage: $0 --dir <backup-dir> --database <database-name>";
  exit 1;
}

my $max = 4;
my $max_old = 24*3600*7;
my($dir,$database);

GetOptions(
  "dir=s" => \$dir,
  "database=s" => \$database
);
(is_string($dir) && -d $dir) or usage();
is_string($database) or usage();

$dir = abs_path($dir);
my $command = "mysqldump $database > %s";

say "directory: $dir";

#create backup
my $file = "$dir/".local_date().".back";
if(-f $file){
  say "backup file $file already exists";
}else{
  my $c = sprintf($command,$file);
  say $c;
  `$c`;
}

#remove old backups
my @files = ();
my @copy = ();

find({
  no_chdir => 1,
  wanted => sub{
    return if -d $_;
    push @files,$_;
  }
},$dir);

#sorteer op mtime
@files = sort_mtime(@files);

say "removing by date modified:";
#verwijderen op datum
for(@files){
  my $mtime = (lstat($_))[9];
  if(($mtime + $max_old) < time){ 
    say "\tremoving $_";
    unlink $_ or die($!);
  }else{
    push @copy,$_;
  }
}

@files = sort_mtime(@copy);

say "removing by count: ";
#verwijderen op aantal
if(scalar(@files) > $max){

  my $num_to_delete = scalar(@files) - $max;

  for(1 .. $num_to_delete){
    my $f = $files[ $_ - 1 ];
    say "\tremoving $f";
    unlink $f or die($!);
  }

}
