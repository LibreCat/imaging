package Imaging::Dir::Query::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
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
        #parse bag-info.txt
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
        #haal (goede) queries op
        if(is_array_ref($baginfo->{'Archive-Id'}) && scalar(@{ $baginfo->{'Archive-Id'} }) > 0){

            @queries = "\"".$baginfo->{'Archive-Id'}->[0]."\"";

        }else{

            @queries = @{$baginfo->{'DC-Identifier'}};
            my @filter = ();
            foreach(@queries){
                if(/^rug01:\d{9}$/o){
                    @filter = $_;
                    last;
                }else{
                    push @filter,$_;
                }
            }
            @queries = @filter;

        }
    };
    @queries;
}   

with qw(Imaging::Dir::Query);

__PACKAGE__;
