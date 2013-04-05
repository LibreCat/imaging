package Imaging::Dir::Query::RUG01;
use Catmandu::Sane;
use File::Basename;
use Moo;

my $re = qr/^RUG01-\d{9}$/;

sub check {
  my($self,$path)=@_;
  defined $path && -d $path && basename($path) =~ $re;
}
sub queries {    
  my($self,$path)=@_;
  return () if !defined($path);
  my $num = substr(basename($path),6,9);
  "rug01:$num";
}

with qw(Imaging::Dir::Query);

1;
