package Imaging::Profile::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Moo;

sub test {
  my($self,$dir)=@_;
  $dir =~ s/\/$//o if $dir;
  return is_string($dir) && -d "$dir/data" && -f "$dir/bagit.txt";
}

with 'Imaging::Profile';

1;
