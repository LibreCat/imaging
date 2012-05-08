package Imaging::Test::Dir::BAG::checkNARA;
use Moo;
use Data::Util qw(:validate);
use Try::Tiny;

has _nara_conf  => (
    is => 'rw',
    default => sub {
        [{
            class => "Imaging::Test::Dir::checkFileExtension",
            args => {
                extensions => ["tif"],
                lookup => "data",
                valid_patterns => ['^(?!RUG01-\d{9}$)']
            }
         },
         {
            class => "Imaging::Test::Dir::checkTIFF",
            args => {
                lookup => "data",
                valid_patterns => ['^(?!RUG01-\d{9}$)']
            }
         },
         {
            class => "Imaging::Test::Dir::NARA::checkFilename",
            args => {
                lookup => "data",
                valid_patterns => ['^(?!RUG01-\d{9}$)']
            }
        }];
    }
);
has _stash => (
    is => 'rw',
    lazy => 1,
    isa => sub { hash_ref($_[0]); },
    default => sub {
        my $self = shift;
        my $stash = {};
        my $nara_conf = $self->_nara_conf;
        foreach my $nara(@$nara_conf){
            $stash->{$nara->{class}} = Catmandu::Util::require_package($nara->{class})->new(%{ $nara->{args} });
        }
        $stash;
    }
);

sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my(@errors) = ();
    my $stash = $self->_stash;
    my $nara_conf = $self->_nara_conf;

    foreach my $nara(@$nara_conf){
        my $ref = $stash->{$nara->{class}};
        $ref->dir($topdir);
        my($success,$errs) = $ref->test();
        push @errors,@$errs if(!$success);
    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
