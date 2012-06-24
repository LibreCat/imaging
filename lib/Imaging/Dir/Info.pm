package Imaging::Dir::Info;
use Catmandu::Sane;
use Data::Util qw(:validate :check);
use Moo;
use File::Basename;
use File::Find;
use Cwd qw(abs_path);
use Try::Tiny;

sub _load_info {
    my $self = shift;
    my $dir = $self->dir;

    my $size = 0;
    my(@files,@directories);
    try{
        find({
            wanted => sub{
                my $path = $File::Find::name;
                return if $path eq $dir;
                my $info = {
                    dirname => $File::Find::dir,
                    basename => basename($path),
                    path => $path
                };
                if(-d $path){
                    $size += -s $path;
                    push @directories,$info;
                }elsif(-f $path){
                    push @files,$info;
                }
            },
            no_chdir => 1
        },$dir);
    };
    $self->size($size);
    $self->files(\@files);
    $self->directories(\@directories);
}

has dir => (
    is => 'rw',
    isa => sub{ (is_string($_[0]) && -d $_[0]) || die("directory not given or does not exist\n"); },
    lazy => 1,
    coerce => sub {
        abs_path($_[0] || "");
    },
    trigger => sub {
        $_[0]->_load_info();
    }
);
has files => (
    is => 'rw',
    isa => sub{ array_ref($_[0]); },
    lazy => 1,
    default => sub{ []; }
);
has directories => (
    is => 'rw',
    isa => sub{ array_ref($_[0]); },
    lazy => 1,
    default => sub{ []; }
);
has size => (
    is => 'rw',
    default => sub { 0; }
);

__PACKAGE__;
