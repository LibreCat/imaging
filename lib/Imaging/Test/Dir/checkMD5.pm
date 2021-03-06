package Imaging::Test::Dir::checkMD5;
use Moo;
use Digest::MD5 qw(md5_hex);
use Cwd qw(abs_path);
use File::Basename;

has name_manifest => (
    is => 'rw',
    default => sub{ "manifest-md5.txt"; }
);
has is_optional => (
    is => 'ro',
    default => sub { 0; }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my $files = $self->dir_info->files();
    my(@errors) = ();

    #find manifest
    my $path_manifest;
    foreach my $stats(@$files){
        if($stats->{basename} eq $self->name_manifest()){
            $path_manifest = $stats->{path};
            last;
        }
    }
    if(!defined($path_manifest)){

        push @errors,$self->name_manifest()." kon niet gevonden worden" if !$self->is_optional();

    }else{
        
        #open manifest: <md5sum> <file>
        my $dirname_manifest = abs_path(dirname($path_manifest));

        local(*MANIFEST);
        my $open_manifest = open MANIFEST,"<:encoding(UTF-8)",$path_manifest;
        if(!$open_manifest){
            push @errors,$!;
        }

        while(my $line = <MANIFEST>){
            chomp($line);
            my($md5sum_original,$filename) = split(/\s+/o,$line);
            if(!defined($filename)){
                push @errors,basename($path_manifest).": formaat incorrect (<md5sum> <path> op elke lijn)";
                last;
            } 
            $filename = "$dirname_manifest/$filename";
            local(*FILE);
            my $open_file = open FILE,"<$filename";
            if(!$open_file){
                push @errors,$!;
                next;
            }
            my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
            close FILE;
            if($md5sum_file ne $md5sum_original){
                push @errors,"checksum voor ".basename($filename)." faalde";
                next;
            }
        }
        close MANIFEST;

    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
