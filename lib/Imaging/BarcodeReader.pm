package Imaging::BarcodeReader;
use Catmandu::Sane;
use Catmandu::Util qw(:is :check);
use Image::Magick;
use Barcode::ZBar;
use Moo;

has config => (
  is => 'ro',
  isa => sub { check_array_ref($_[0]); },
  default => sub {
    ["enable"];
    #to disable all fourcc except code128
    #vb. [qw(disable code128.enable)]
  }
);
has scanner => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = $_[0];
    my $s = Barcode::ZBar::ImageScanner->new();
    $s->parse_config($_) for @{ $self->config };
    $s;
  }
);
sub read_barcodes {
  my($self,$file) = @_;
  say "checking $file";
  # obtain image data
  my $magick = Image::Magick->new();
  my $error = $magick->Read($file);
  my $raw = $magick->ImageToBlob(magick => 'GRAY', depth => 8);

  # wrap image data
  my $image = Barcode::ZBar::Image->new();
  $image->set_format('Y800');
  $image->set_size($magick->Get(qw(columns rows)));
  $image->set_data($raw);

  # scan the image for barcodes
  $self->scanner()->scan_image($image);
  $image->get_symbols();
}

1;
