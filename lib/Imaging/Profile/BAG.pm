package Imaging::Profile::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Moo;

sub test {
    my($self,$dir)=@_;
    $dir =~ s/\/$//o if $dir;
    is_string($dir) &&
    -d "$dir/data" && 
    -f "$dir/manifest-md5.txt" &&
    -f "$dir/bagit.txt" &&
    -f "$dir/bag-info.txt"
}

with 'Imaging::Profile';

__PACKAGE__;