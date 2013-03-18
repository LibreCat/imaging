package Imaging::Profiles;
use Catmandu::Sane;
use Catmandu::Util qw(require_package);
use Data::Util qw(:check :validate);
use Moo;

has list => (
  is => 'rw',
  lazy => 1,
  isa => sub {
    my $a = $_[0];
    array_ref($a) && do {
      my $success = 1;
      foreach my $pair(@$a){
        if(!(is_array_ref($pair) && scalar(@$pair) == 2)){
          $success = 0;
          last;
        }
      }
      $success;
    } or die("format: [ ['Bag','Imaging::Profile::Bag'],['TAR','Imaging::Profile::TAR'], .. ]\n");
  },
  default => sub{ []; }
);
sub profile {
  state $packages = {};
  my($self,$package_name)=@_;
  $packages->{$package_name} ||= require_package($package_name)->new;
}

sub get_profile {
  my($self,$dir)=@_;

  #laatste profile geldt als default, en moet je dus niet testen
  for(my $i = 0;$i < scalar(@{ $self->list }) - 1;$i++){
    my($profile_id,$package_name) = @{ $self->list->[$i] };
    my $ref = $self->profile($package_name);
    if($ref->test($dir)){ 
      return $profile_id; 
    }
  }
  return (scalar(@{ $self->list }) > 0) ? $self->list->[-1]->[0] : undef;
}

__PACKAGE__;
