package Imaging::Bag::Info;
use Catmandu::Sane;
use Moo;
use Data::Util qw(:check :validate);
use Catmandu::Util qw(:io);
use Clone qw(clone);

has source => (
  is => 'rw',
  required => 0,
  lazy => 1,
  trigger => sub {
    $_[0]->_source( io( $_[0]->source(),'binmode' => 'utf8' ) );
  }
);
has _source => (
  is => 'rw',
  lazy => 1,
  trigger => \&_build_hash
);
has _hash => (
  is => 'rw',
  isa => sub { hash_ref($_[0]); },
  required => 0,
  lazy => 1,
  default => sub { {}; }
);
sub trim {
  my $str = shift;
  $str =~ s/^\s+//go;
  $str =~ s/\s+$//go;
  #remove BOM (yuk!)
  $str =~ tr/\x{feff}//d;
  $str;
}
sub _build_hash {
  my $self = shift;
  my $source = $self->_source();
  my $hash = {};
  if(defined($source) && $source->opened && !$source->error){
    my($line,$key);
    while(defined($line = $source->getline)){
      $line =~ s/\r\n$/\n/o;
      chomp($line);
      my $index = index($line,':');
      #eerste lijn key : value
      if($index >= 0){
        $key = trim( substr($line,0,$index) );
        my $value = trim( substr($line,$index + 1) );
        $hash->{$key} ||= [];
        push @{$hash->{$key}},$value;
      }elsif(defined($key)){
        $line =~ s/^\t+//go;
        $hash->{$key}->[-1] .= $line;
      }
    }
    $source->close;
  }
  $self->_hash($hash);
}
sub hash {
  clone($_[0]->_hash);
}
sub keys {
  my $self = shift;
  keys %{ $self->_hash() };
}
sub values {
  my($self,$key) = @_;
  my @values = @{ $self->_hash()->{$key} };    
}

__PACKAGE__;
