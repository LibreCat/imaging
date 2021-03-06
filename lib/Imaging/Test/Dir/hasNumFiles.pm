package Imaging::Test::Dir::hasNumFiles;
use Moo;
use File::Basename;

has _pattern => (
    is => 'rw',
    lazy => 1,
    isa => sub {
        my $self = shift;
        my $pattern = $self->pattern;
        qr/$pattern/;
    }
);
has pattern => (
    is => 'rw',
    default => sub{
        '.*';
    }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my $files = $self->dir_info->files();
    my(@errors) = ();

    my $num = 0;
    foreach my $pattern(@{ $self->patterns }){
        foreach my $stats(@$files){
            $num++ if $stats->{basename} =~ $pattern;
        }
    }   
    if($num == 0){
        push @errors,basename($topdir).": geen bestanden voldoen aan patroon ".$self->pattern;
    }
    
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
