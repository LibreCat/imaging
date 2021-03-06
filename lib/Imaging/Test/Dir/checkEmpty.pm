package Imaging::Test::Dir::checkEmpty;
use Moo;

has inverse => (
  is => 'ro',
  default => sub { 0; }
);

sub is_fatal { 1; }

sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my $files = $self->dir_info->files();
  my(@errors) = ();
  foreach my $stats(@$files){
    next if !$self->is_valid_basename($stats->{basename});
 
    #file mag niet empty leeg zijn
    if($self->inverse){
      if((-s $stats->{path}) == 0){
        push @errors,$stats->{basename}." is een leeg bestand";
      }
    }
    #file moet leeg zijn
    else{
      if((-s $stats->{path}) > 0){
        push @errors,$stats->{basename}." moet een leeg bestand zijn";
      }
    }
  }
  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
