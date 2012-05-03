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
            die("is geen geldige pdf\n") if !defined($pdf);
            die("volgens de pdf permissies kan dit niet worden geprint\n") if !$pdf->canPrint();
            die("volgens de pdf permissies kan dit niet worden gekopiëerd\n") if !$pdf->canCopy();
        }catch {
            chomp($_);
            push @errors,"fout in pdf ".$stats->{path}.":$_";
        };
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
