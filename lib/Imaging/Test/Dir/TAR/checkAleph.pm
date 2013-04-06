package Imaging::Test::Dir::TAR::checkAleph;
use Moo;
use Try::Tiny;
use Data::Util qw(:check :validate);
use File::Basename;
use File::Spec;
use Catmandu;

has store => ( is => 'ro' );
has bag => ( is => 'ro' );
has _bag => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = $_[0];
    Catmandu->store($self->store)->bag($self->bag);
  }
);

has _re => (
  is => 'ro',
  default => sub { qr/^RUG01-(\d{9})$/; }
);
sub is_fatal { 0; }

sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my $basename_topdir = basename($topdir);
  my(@errors) = ();
  my $query = "";

  my $fSYS;
  if($basename_topdir =~ $self->_re){

    $fSYS = $1;

  }else{

    my @rug01_files = grep { 
      $_ =~ /RUG01-(\d{9})$/o && ($fSYS = $1)
    } glob("$topdir/*");
    my $num_rug01_files = scalar(@rug01_files);

    if($num_rug01_files == 0){

      push @errors,"$basename_topdir: geen rug01-bestand gevonden";

    }elsif($num_rug01_files > 1){

      push @errors,"$basename_topdir: meer dan één rug01-bestand gevonden";

    }
  }
  if(scalar(@errors) == 0 && is_string($fSYS)){

    $query = "rug01:$fSYS";
    try{
      my $res = $self->_bag->search(query => $query,fq => 'source:rug01',limit => 0);
      if($res->total <= 0){
        push @errors,"$query leverde geen resultaten op in Aleph";
      }
    }catch{
      push @errors,$_;
    };

  }
  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
