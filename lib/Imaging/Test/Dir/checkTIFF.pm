package Grim::Test::Dir::checkTIFF;
use Moo;
use Image::ExifTool;

has _exif => (
	is => 'ro',
	default => sub{ Image::ExifTool->new; }
);
sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();
	foreach my $stats(@$file_info){
		next if !$self->is_valid_basename($stats->{basename});
		my $exif = $self->_exif->ImageInfo($stats->{path});
		if($exif->{Error}){
			push @errors,[$stats->{path},"EXIF_FAILED",$exif->{Error}];
		}elsif(!(uc($exif->{FileType}) eq "TIFF" && $exif->{MIMEType} eq "image/tiff")){
			push @errors,[$stats->{path},"IS_NOT_A_TIFF",$stats->{path}." is not a tiff"];	
		}
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Grim::Test::Dir);

1;
