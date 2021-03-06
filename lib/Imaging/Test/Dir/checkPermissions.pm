package Imaging::Test::Dir::checkPermissions;
use Moo;

sub is_fatal {
    1;
};

sub test {
    my $self = shift;
    my $files = $self->dir_info->files();
    my $directories = $self->dir_info->directories();
    my(@errors) = ();
    foreach my $stats(@$files,@$directories){
        if(!-r $stats->{path}){
            push @errors,$stats->{basename}." is niet leesbaar";
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
