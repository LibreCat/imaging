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
        $_[0]->_source( io( $_[0]->source() ) );
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
    $str;
}
sub _build_hash {
    my $self = shift;
    my $source = $self->_source();
    my $hash = {};
    if(defined($source) && $source->opened && !$source->error){
        my $line;
        while(defined($line = $source->getline)){
            $line =~ s/\r\n$/\n/o;
            chomp($line);
            say $line;
            my $index = index($line,':');
            if($index >= 0){
                my $key = trim( substr($line,0,$index) );
                my $value = trim( substr($line,$index + 1) );
                $hash->{$key} ||= [];
                push @{$hash->{$key}},$value;
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
