package Imaging::Test::Dir::checkPermissions;
use Moo;

sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();
	foreach my $stats(@$file_info){
		if(!-r $stats->{path}){
			push @errors,$stats->{path}." is not readable or does not exist";
		}
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Imaging::Test::Dir);

1;
