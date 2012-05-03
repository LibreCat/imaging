package Imaging::Test::Dir::checkFilePattern;
use Moo;

has pattern => (
    is => 'rw',
    isa => sub {
        rx($_[0]);
    },
    default => sub{
        qr/.*/;
    }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my $file_info = $self->file_info();
    my(@errors) = ();
    my $pattern = $self->pattern;

    foreach my $stats(@$file_info){
        if($stats->{basename} !~ $pattern){
            push @errors,"$stats->{basename} voldoet niet aan het vereiste bestandspatroon ($pattern)";
        }
    }
    
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
