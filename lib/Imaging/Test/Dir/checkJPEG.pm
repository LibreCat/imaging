package Imaging::Test::Dir::checkJPEG;
use Moo;
use Image::ExifTool;
use File::MimeInfo;

has _exif => (
    is => 'ro',
    default => sub{ Image::ExifTool->new; }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my $files = $self->dir_info->files();
    my(@errors) = ();
    foreach my $stats(@$files){
        next if !$self->is_valid_basename($stats->{basename});
        my $exif = $self->_exif->ImageInfo($stats->{path});
        if($exif->{Error}){
            push @errors,$stats->{basename}." is geen foto";
        }elsif(!(uc($exif->{FileType}) eq "JPEG" && $exif->{MIMEType} eq "image/jpeg")){
            push @errors,$stats->{basename}." is geen jpeg (bestandstype gevonden:".mimetype($stats->{path}).")";    
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
