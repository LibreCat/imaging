package Imaging::Test::Dir::hasFiles;
use Moo;
use Data::Util qw(:check :validate);

has patterns => (
    is => 'rw',
    isa => sub {
        my $array = shift;      
        array_ref($array);
        foreach(@$array){
            if(!is_rx($_)){
                $_ = qr/$_/;
            }
        }
        rx($_) foreach(@$array);
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
    my $files = $self->dir_info->files();
    my(@errors) = ();

    foreach my $pattern(@{ $self->patterns }){
        my $found;
        foreach my $stats(@$files){
            $found = $stats if $stats->{basename} =~ $pattern;
        }
        if(!$found){
            push @errors,"bestandspatroon $pattern niet gevonden in deze map";
        }
    }
    
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
