package Imaging::Test::Dir::checkTIFF;
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
    my $files = $self->dir_info->files();
    my(@errors) = ();
    foreach my $stats(@$files){
        next if !$self->is_valid_basename($stats->{basename});
        my $exif = $self->_exif->ImageInfo($stats->{path});
        if($exif->{Error}){
            push @errors,$stats->{basename}." is geen foto";
        }elsif(!(uc($exif->{FileType}) eq "TIFF" && $exif->{MIMEType} eq "image/tiff")){
            push @errors,$stats->{basename}." is geen tif (bestandstype gevonden:".mimetype($stats->{path}).")";    
        }
    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
