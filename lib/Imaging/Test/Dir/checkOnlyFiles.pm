package Imaging::Test::Dir::checkOnlyFiles;
use Moo;

sub is_fatal {
    1;
};

sub test {
    my $self = shift;
    my $files = $self->dir_info->files();
    my(@errors) = ();
    foreach my $stats(@$files){
        next if !$self->is_valid_basename($stats->{basename});
        if(!-f $stats->{path}){
            push @errors,$stats->{basename}." is geen normaal bestand";
        }elsif(-l $stats->{path}){
            push @errors,$stats->{basename}." is een symbolic link";
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
