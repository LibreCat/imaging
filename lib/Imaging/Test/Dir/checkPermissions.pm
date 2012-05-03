package Imaging::Test::Dir::checkPermissions;
use Moo;

sub is_fatal {
    1;
};

sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my $file_info = $self->file_info();
    my(@errors) = ();
    foreach my $stats(@$file_info){
        if(!-r $stats->{path}){
            push @errors,$stats->{basename}." is niet leesbaar of bestaat niet";
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
