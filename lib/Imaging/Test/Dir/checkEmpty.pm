package Grim::Test::Dir::checkEmpty;
use Moo;

sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();
	foreach my $stats(@$file_info){
		next if !$self->is_valid_basename($stats->{basename});
		if((-s $stats->{path}) == 0){
			push @errors,[$stats->{path},"FILE_IS_EMPTY",$stats->{path}." is empty"];
		}
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Grim::Test::Dir);

1;
