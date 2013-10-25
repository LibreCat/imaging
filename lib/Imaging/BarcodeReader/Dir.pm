package Imaging::BarcodeReader::Dir;
use Catmandu::Sane;
use Catmandu::Util qw(:is :io :check);
use Moo;
use Data::Dumper;

extends qw(Imaging::BarcodeReader);

has extensions => (
  is => 'ro',
  isa => sub { check_array_ref($_[0]); },
  lazy => 1,
  default => sub { ["enable"]; }
);
has max => (
  is => 'ro',
  isa => sub { check_integer($_[0]); },
  lazy => 1,
  default => sub { -1; }
);

sub is_valid_file {
  my($self,$file)=@_;

  state $re = do {
    my $r;
    if(scalar(@{ $self->extensions })){
      my $j = join('|',@{ $self->extensions });
      $r = qr/\.(?:$j)$/;
    }else{
      $r = qr/.*/;
    }
  };

  lc($file) =~ $re;
} 
around read_barcodes  => sub {
  my($orig,$self,$dir)=@_;

  my @barcodes;

  my @files = grep { $self->is_valid_file($_) } $self->read_dir($dir);
  for(my $i = 0;$i < scalar(@files);$i++){
    last if $self->max >= 0 && $i >= $self->max;
    my $file = $files[$i];
    @barcodes = $orig->($self,$file);
    print Dumper(\@barcodes);
    last if @barcodes;
  }

  @barcodes;
};
sub read_dir {
  my($self,$dir) = @_;
  local(*D);
  opendir(D,$dir) or die($!);
  my @files = map { join_path($dir,$_); } sort { lc($a) cmp lc($b) } grep { $_ ne "." && $_ ne ".." } readdir(D);
  closedir(D);
  @files;
}

1;
