package Imaging::Test::Dir::checkPDF;
use Moo;
use CAM::PDF;
use Try::Tiny;

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
        try{
            my $pdf = CAM::PDF->new($stats->{path});
            die("is geen pdf\n") if !defined($pdf);
            die("pdf kan niet worden geprint\n") if !$pdf->canPrint();
            die("pdf kan niet worden gekopiëerd\n") if !$pdf->canCopy();
        }catch {
            push @errors,"fout in pdf ".$stats->{path}.":$_";
        };
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
