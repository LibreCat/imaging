package Imaging::Test::Dir::TAR::checkFilename;
use Moo;
use Data::Util qw(:check);

sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my $basename_topdir = basename($topdir);
    my $file_info = $self->file_info();
    my(@errors) = ();

    #zit er wel iets in?
    if(scalar(@$file_info)<=0){
        push @errors,"Deze map is leeg";
    }

    my $re = qr/^${basename_topdir}_(\d{4})_0001_MA\.pdf$/;

    my @pdfs = grep {
        $_->{basename} =~ $re;
    } @$file_info;

    my $num = scalar(@pdfs);
    if($num <=0){

        push @errors,"$basename_topdir: ${basename_topdir}_<jaartal>_0001_MA.pdf niet gevonden"; 

    }elsif($num > 1){

        push @errors,"$basename_topdir: meer dan één master tif gevonden, maar van ander jaartal";

    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
