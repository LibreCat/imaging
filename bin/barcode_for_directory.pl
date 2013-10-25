#!/usr/bin/perl
use Catmandu::Sane;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu::Util qw(:is);
use Imaging::BarcodeReader::Dir;
use Catmandu::Exporter::CSV;
use Getopt::Long;
use Cwd;

my($extensions,$verbose,$max,$help) = ([qw()],0,-1,0);

sub error {
  print STDERR $_[0];
  exit(1);
}
sub usage {
  error(<<EOF
usage: $0 [OPTIONS] <dir1> <dir2> ..
options:
  extensions  extensions to be processed (default: all)
  max         max files to be processed (default: -1)
  verbose     print log info to standard error (default: disabled)
  help        show this message
output: csv
  directory,barcode
  <dir1>,<barcode>
  <dir2>,<barcode>
  ..
EOF
  );
}
sub log_info {
  say STDERR $_[0] if $verbose;
}
sub exporter { state $e = Catmandu::Exporter::CSV->new(fields => [qw(directory barcode)]); }

GetOptions(
  "extensions=s" => $extensions,
  "verbose" => \$verbose,
  "max=i" => \$max,
  "help" => \$help
);

usage() if $help;

my $barcode_reader = Imaging::BarcodeReader::Dir->new(
  max => $max,
  extensions => $extensions
);

for my $dir(@ARGV){
  unless(-d $dir){
    log_info("$dir is not a directory");
    next;
  }
  my @barcodes = $barcode_reader->read_barcodes($dir);
  exporter()->add({
    directory => Cwd::abs_path($dir),
    barcode => ($barcodes[0] ? $barcodes[0]->get_data() : undef)
  });
}
exporter()->commit();
