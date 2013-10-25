package Imaging::Dir::Query::Barcode;
use Catmandu::Sane;
use File::Basename;
use Moo;

my $barcode_re = qr/^(?:9000|0000)\d{8}$/;

sub check {
  my($self,$path) = @_;
  defined $path && -d $path && basename($path) =~ $barcode_re;
}
sub queries {    
  my($self,$path) = @_;
  basename($path);
} 

with qw(Imaging::Dir::Query);

1;
