package Imaging::Test::Dir::checkFilePattern;
use Data::Util qw(:validate);
use Moo;

has pattern => (
  is => 'rw',
  isa => sub {
    rx($_[0]);
  },
  default => sub{
    qr/.*/;
  }
);
sub is_fatal { 1; }
sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my $files = $self->dir_info->files();
  my(@errors) = ();
  my $pattern = $self->pattern;

  foreach my $stats(@$files){
    if($stats->{basename} !~ $pattern){
      push @errors,"$stats->{basename} voldoet niet aan het vereiste bestandspatroon ($pattern)";
    }
  }
  
  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
