package Imaging::Test::Dir::checkOnlyFiles;
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
        if(!-f $stats->{path}){
            push @errors,$stats->{basename}." is geen normaal bestand (waarschijnlijk een map)";
        }elsif(-l $stats->{path}){
            push @errors,$stats->{basename}." is een symbolic link";
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
