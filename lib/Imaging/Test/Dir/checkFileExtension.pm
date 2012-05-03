package Imaging::Test::Dir::checkFileExtension;
use Moo;

has extensions => (
    is => 'rw',
    isa => sub {
        Data::Util::array_ref($_[0]);
        Data::Util::is_string($_) or die("array value must be string\n") foreach(@{ $_[0] });
    },
    default => sub{
        [];
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
    my $extensions = $self->extensions;

    foreach my $stats(@$file_info){
        my $index = rindex($stats->{basename},".");
        if($index >= 0){
            my $ext = substr($stats->{basename},$index + 1);
            my $found = 0;
            foreach my $extension(@$extensions){
                if($extension eq $ext){
                    $found = 1;
                }
            }
            if(!$found){
                push @errors,"$stats->{basename}: extensie '$ext' is niet toegelaten";
            }
        }else{
            push @errors,"$stats->{basename} heeft geen extensie";
        }
    }
    
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
