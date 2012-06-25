package Imaging::Profile::TAR;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Moo;

sub test {
    my($self,$dir)=@_;
    $dir =~ s/\/$//o if $dir;
    return is_string($dir) && -d $dir && -f "$dir/__TAR.txt";
}

with 'Imaging::Profile';

__PACKAGE__;
