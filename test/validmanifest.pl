#!/usr/bin/env perl
use Catmandu::Sane;
use Data::Util qw(:check);
use Try::Tiny;

sub has_manifest {
    my $path = shift;
    is_string($path) && -f "$path/manifest-md5.txt";
}
sub has_valid_manifest {
    state $line_re = qr/^[0-9a-fA-F]+\s+.*$/;

    my $path = shift;
    has_manifest($path) && do {
        my $valid = 0;
        try{
            local(*FILE);
            my $line;
            open FILE,"$path/manifest-md5.txt" or die($!);
            while($line = <FILE>){
                $line =~ s/\r\n$/\n/;
                chomp($line);
                utf8::decode($line);
                if($line !~ $line_re){
                    last;
                }
            }
            close FILE;
            $valid = 1;
        }catch {
            say STDERR $_;
        };
        $valid;
    };
}
say "manifest:".(has_valid_manifest(shift) ? "valid":"not valid");
