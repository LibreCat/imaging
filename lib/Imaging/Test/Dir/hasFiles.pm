package Imaging::Test::Dir::hasFiles;
use Moo;

has patterns => (
    is => 'rw',
    isa => sub {
        my $array = shift;      
        Data::Util::array_ref($array);
        foreach(@$array){
            if(!is_rx($_)){
                $_ = qr/$_/;
            }
        }
        Data::Util::rx($_) foreach(@$array);
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

    foreach my $pattern(@{ $self->patterns }){
        my $found;
        foreach my $stats(@$file_info){
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
