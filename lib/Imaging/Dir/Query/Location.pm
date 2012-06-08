package Imaging::Dir::Query::Location;
use Catmandu::Sane;
use File::Basename;
use Moo;

my $re = qr/^[a-zA-Z0-9]+(?:\-[a-zA-Z0-9]+)*$/;
my $re_not = qr/^RUG01-/;

sub check {
    my($self,$path)=@_;
    my $basename = basename($path);
    defined $path && -d $path && $basename !~ $re_not && $basename =~ $re;
}
sub queries {
    my($self,$path)=@_;
    return () if !defined($path);
    "location:".basename($path);
}

with qw(Imaging::Dir::Query);

__PACKAGE__;
