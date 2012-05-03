#!/usr/bin/env perl
use Catmandu::Sane;
use File::Basename;

my $re = qr/^([\w_\-]+)_(\d{4})_(\d{4})_(MA|ST)\.([a-zA-Z]+)$/;
foreach my $file(@ARGV){
    $file = basename($file);
    if($file =~ $re){
        say "$file ok";
    }else{
        say "$file not ok (1:$1,2:$2,3:$3,4:$4,5:$5)";
    }
}
