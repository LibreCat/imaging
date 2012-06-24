package Imaging::Test::Dir;
use Catmandu::Sane;
use Data::Util qw(:check :validate);
use Imaging::Dir::Info;

use Moo::Role;

sub is_valid_basename {
    my($self,$basename)=@_;
    foreach my $pattern(@{ $self->valid_patterns }){
        return 1 if $basename =~ $pattern;
    }
    return 0;
}

has dir_info => (
    is => 'rw',
    isa => sub { instance($_[0],"Imaging::Dir::Info"); }
);
has valid_patterns => (
    is => 'rw',
    isa => sub{ 
        my $array = shift;
        array_ref($array);
        foreach(@$array){
            if(!is_rx($_)){
                $_ = qr/$_/;
            }
        }
        rx($_) foreach(@$array);
    },
    default => sub {
        [qr/.*/];
    }
);

requires 'test';
requires 'is_fatal';

1;
