package Imaging::Test::Dir::NARA::checkAleph;
use Moo;
use Catmandu;
use Data::Util qw(:validate);
use File::Basename;
use Try::Tiny;

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
sub is_fatal { 0; }

sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my(@errors) = ();
  my $query = basename($topdir);

  if($query =~ /^RUG(\d{2})-(\d{9})$/o){
    $query = "rug$1:$2";
  }

  try{
    my $res = $self->_bag->search(query => $query,fq => 'source:rug01',limit => 0);
    if($res->total <= 0){
      push @errors,"$query niet gevonden in Aleph";
    }
  }catch{
    push @errors,$_;
  };

  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
