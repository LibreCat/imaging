package Imaging::Test::Dir::TAR::checkFilename;
use Moo;
use Data::Util qw(:check);
use File::Basename;

sub is_fatal {
    1;
};
sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my $basename_topdir = basename($topdir);
  my $files = $self->dir_info->files();
  my $directories = $self->dir_info->directories();
  my(@errors) = ();

  #zit er wel iets in?
  if(scalar(@$files)<=0 && scalar(@$directories) <= 0){
    push @errors,"Deze map is leeg";
  }
  my $re = qr/^${basename_topdir}_\d{4}_0001_AC\.\w+$/;
  my @acs = grep {
    $_->{basename} =~ $re;
  } @$files;

  my $num = scalar(@acs);
  if($num <=0){

    push @errors,"$basename_topdir: ${basename_topdir}_<jaartal>_0001_AC.<extension> niet gevonden"; 

  }elsif($num > 1){

    push @errors,"$basename_topdir: meer dan één AC gevonden:";
    $topdir =~ s/\/$//o;
    for(@acs){
      my $subname = $_->{path};
      $subname =~ s/^$topdir\///g;
      push @errors," $subname";
    }

  }

  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
