package Imaging::Test::Dir::scan;
use Moo;
use ClamAV::Client;
use Data::Util qw(:check :validate);
use Cwd qw(abs_path);

has _scanner => (
  is => 'ro',
  isa => sub {
      instance($_[0],"ClamAV::Client");
  },
  lazy => 1,
  default => sub { ClamAV::Client->new(); }
);
sub is_fatal {
    1;
};
sub test {
  my $self = shift;
  my $topdir = $self->dir_info->dir();
  my(@errors) = ();
  my %results = ();
  local($@) = undef;
  $@ = undef;
  eval{
      %results = $self->_scanner->scan_path_complete(abs_path($topdir));
  };
  if($@){
      push @errors,$@->{'-text'};
  };
  while(my($path,$result)=each %results){
      push @errors,$result;
  }
  scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
