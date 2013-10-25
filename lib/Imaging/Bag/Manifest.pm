package Imaging::Bag::Manifest;
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
sub _build_hash {
  my $self = shift;
  my $source = $self->_source();
  my $hash = {};
  if(defined($source) && $source->opened && !$source->error){

    my($line);

    while(defined($line = $source->getline)){
      $line =~ s/\r\n$/\n/o;
      chomp($line);

      my($md5,$file) = split(/\s+/o,$line);
      $hash->{$file} = $md5;

    }

    $source->close;
  }
  $self->_hash($hash);
}
sub hash {
  clone($_[0]->_hash);
}
sub files {
  keys %{ $_[0]->_hash() };
}
sub md5 {
  my($self,$file) = @_;
  exists($self->_hash()->{$file}) && is_array_ref($self->_hash()->{$file}) ? @{ $self->_hash()->{$file} } : ();    
}

1;
