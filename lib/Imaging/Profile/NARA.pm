package Imaging::Profile::NARA;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename;
use Moo;

sub test {
    my($self,$dir)=@_;
    $dir =~ s/\/$//o if $dir;
    return is_string($dir) && -d $dir &&
    do {
        my @files = glob "$dir/*";
        my $success = 1;
        #enkel bestanden
        foreach my $file(@files){
            if(-d $file){
                $success = 0;
                last;               
            }
        }
        #tiffs of manifest-md5.txt of __FIXME.txt
        if($success){
            my @valid = grep { 
                my $name = basename($_);
                $name =~ /_MA\.tif$/o || $name =~ /^__MANIFEST-MD5\.txt$/o || $name =~ /^__FIXME\.txt$/o 
            } @files;
            $success = scalar(@valid) == scalar(@files);
        }

        $success;
    };
}

with 'Imaging::Profile';

__PACKAGE__;
