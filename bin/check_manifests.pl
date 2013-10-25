#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu::Sane;
use Imaging::Bag::Manifest;
use File::Basename;
use Digest::MD5 qw(md5_hex);

for my $manifest_file(@ARGV){

  if(! -f $manifest_file){

    say STDERR "$manifest_file is not a file";
    next;

  }

  my $dir = dirname($manifest_file);

  my $manifest = Imaging::Bag::Manifest->new(source => $manifest_file)->hash;

  for my $file(sort keys %$manifest){
    my $md5_expected = $manifest->{$file};
    my $real_file = "$dir/$file";
    open my $fh,$real_file or die($!);
    my $md5_computed = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh;
    if($md5_expected eq $md5_computed){
      say "$real_file: md5 OK";
    }else{
      say STDERR "$real_file: md5 wrong";
    }
  }

}
