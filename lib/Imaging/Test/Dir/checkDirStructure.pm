package Imaging::Test::Dir::checkDirStructure;
use Moo;
use Catmandu::Util qw(:check);

has conf => (
    is => 'ro',
    lazy => 1,
    isa => sub {
        my $hash = $_[0];
        hash_ref($hash);
        for(qw(glob all message)){
            exists($hash->{$_}) or die("configuration key '$_' is not given\n");
        }
    },
    default => sub { 
        {
            glob => "*",
            all => 1,
            message => "missing files in directory"
        }; 
    }
);

sub is_fatal {
    1;
};

sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my $total = scalar(@{ $self->dir_info->files }) + scalar(@{ $self->dir_info->directories });
    my(@errors) = ();

    my $glob = "$topdir/".$self->conf->{glob};
    my @files = glob $glob;

    if(
        (scalar @files == 0) ||
        ($self->conf->{all} && scalar(@files) != $total)
    ){
        push @errors,$self->conf->{message};
    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
