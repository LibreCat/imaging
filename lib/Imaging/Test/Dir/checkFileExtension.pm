package Imaging::Test::Dir::checkFileExtension;
use Moo;
use Data::Util qw(:check :validate);

has extensions => (
  is => 'rw',
  isa => sub {
    array_ref($_[0]);
    is_string($_) or die("array value must be string\n") foreach(@{ $_[0] });
  },
  default => sub{ []; }
);
sub is_fatal { 1; }

sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my $files = $self->dir_info->files();
  my(@errors) = ();
  my $extensions = $self->extensions;

  foreach my $stats(@$files){
    next if !$self->is_valid_basename($stats->{basename});
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
