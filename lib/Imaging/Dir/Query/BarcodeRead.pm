package Imaging::Dir::Query::BarcodeRead;
use Catmandu::Sane;
use Catmandu::Util qw(:check);
use Imaging::BarcodeReader::Dir;
use File::Basename;
use Moo;

has max => (  
  is => 'ro',
  isa => sub { check_natural($_[0]); },
  default => sub {
    2;
  }
);
has extensions => (  
  is => 'ro',
  isa => sub { check_array_ref($_[0]); },
  default => sub {
    [qw(tif)]
  }
);
has config => (  
  is => 'ro',
  isa => sub { check_array_ref($_[0]); },
  default => sub {
    [qw(disable code128.disable)]
  }
);

has _barcode_reader => (
  is => 'ro',
  lazy => 1,
  builder => '_build_barcode_reader'
);

sub _build_barcode_reader {
  my $self = shift; 
  Imaging::BarcodeReader::Dir->new(
    config => $self->config,
    max => $self->max,
    extensions => $self->extensions
  );
}

sub check {
  my($self,$path) = @_;
  defined $path && -d $path;
}
sub queries {    
  my($self,$path) = @_;
  my @barcodes = $self->_barcode_reader->read_barcodes($path);
  map { $_->get_data() } @barcodes;
} 

with qw(Imaging::Dir::Query);

1;
