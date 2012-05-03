package Imaging::Test::Dir::checkEmpty;
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
        next if !$self->is_valid_basename($stats->{basename});
        if((-s $stats->{path}) == 0){
            push @errors,$stats->{path}." is een leeg bestand";
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
