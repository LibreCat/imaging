package Imaging::Dir::Query::BAG;
use Catmandu::Sane;
use Try::Tiny;
use Moo;

sub check {
    my($self,$path) = @_;
    defined $path && -d $path && -f "$path/bag-info.txt";
}
sub trim {
    my $str = shift;
    $str =~ /^\s+/go;
    $str =~ /\s+$/go;
    $str;
}
sub queries {    
    my($self,$path) = @_;
    return () if !defined($path);
    my $path_baginfo = "$path/bag-info.txt";
    my @queries = ();
    try{
        local(*FILE);
        my $line;
        my $baginfo = {};
        open FILE,$path_baginfo or die($!);
        while($line = <FILE>){
            chomp($line);            
            utf8::decode($line);
            $line =~ /^\s*(\S+)\s*:\s*(\S+)\s*$/;
            my($key,$val) = ($1,$2);
            $baginfo->{$key} ||= [];
            push @{$baginfo->{$key}},$val;
        }
        close FILE;
        @queries = @{$baginfo->{'DC-Identifier'}};
    };
    @queries;
}   

with qw(Imaging::Dir::Query);

__PACKAGE__;
