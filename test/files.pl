#!/usr/bin/env perl
use Catmandu::Sane;
use File::Find;
use Cwd qw(abs_path);

my @files = ();
find({
    wanted => sub{
        push @files,abs_path($File::Find::name);
    },
    no_chdir => 1,
},shift || ".");
say $_ foreach(@files);
