package Imaging::Test::Dir;
use Catmandu::Sane;
use Catmandu::Util qw(require_package);
use Data::Util qw(:check :validate);
use Moo::Role;
use File::Basename;
use File::Find;
use File::Spec;
use Cwd qw(cwd getcwd fastcwd fastgetcwd chdir abs_path fast_abs_path realpath fast_realpath);
use Try::Tiny;
use File::MimeInfo;

sub import {
    Catmandu::Util->import("require_package");
    Data::Util->import(qw(:check :validate));
    File::Basename->import(qw(basename dirname)); 
    File::Find->import(qw(find finddepth));
    Cwd->import(qw(cwd getcwd fastcwd fastgetcwd chdir abs_path fast_abs_path realpath fast_realpath));
    Try::Tiny->import;
    File::MimeInfo->import(qw(mimetype));
}

sub _load_file_info {
    my $self = shift;
    my @file_info = ();
    my $lookup_dir = $self->dir;
    my $lookup = $self->lookup();
    if(is_string($lookup) && $lookup ne "."){

        $lookup_dir = Cwd::realpath(File::Spec->catdir($lookup_dir,$lookup));

    }
    try{
        find({
            wanted => sub{
                return if abs_path($_) eq abs_path($lookup_dir);
                return if -d abs_path($_);
                push @file_info,{
                    dirname => abs_path($File::Find::dir),
                    basename => basename($_),
                    path => abs_path($File::Find::name)
                };
            },
            no_chdir => 1
        },$lookup_dir);
    };
    $self->file_info(\@file_info);
}
sub is_valid_basename {
    my($self,$basename)=@_;
    foreach my $pattern(@{ $self->valid_patterns }){
        return 1 if $basename =~ $pattern;
    }
    return 0;
}

has lookup => (
    is => 'rw',
    isa => sub {
        is_string($_[0]) or die("lookup must be string\n");
    },
    default => sub {    
        return "."; 
    }
);
has dir => (
    is => 'rw',
    isa => sub{ (is_string($_[0]) && -d $_[0]) || die("directory not given or does not exist"); },
    lazy => 1,
    trigger => sub {
        $_[0]->_load_file_info();
    }
);
has file_info => (
    is => 'rw',
    isa => sub{ array_ref($_[0]); },
    lazy => 1,
    default => sub{ []; }
);
has valid_patterns => (
    is => 'rw',
    isa => sub{ 
        my $array = shift;
        array_ref($array);
        foreach(@$array){
            if(!is_rx($_)){
                $_ = qr/$_/;
            }
        }
        rx($_) foreach(@$array);
    },
    default => sub {
        [qr/.*/];
    }
);

requires 'test';
requires 'is_fatal';

1;
