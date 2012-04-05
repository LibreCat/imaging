package Grim::Test::Dir::checkAlephID;
use Moo;

sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();

	my $aleph_file;
	foreach my $stats(@$file_info){
		if($stats->{basename} =~ /^RUG01-\d{9}$/){ 
			$aleph_file = $stats; 
			last;
		}
	}
	#file found: now make sure the topdir is not the same!
	if($aleph_file){
		if($topdir =~ /^RUG01-\d{9}$/){
			push @errors,[$topdir,"DIR_AND_ALEPH_FILE_ARE_EQUAL","The aleph file ".$aleph_file->{path}." equals directory name $topdir"];
		}	
	}else{
		if(basename($topdir) !~ /^RUG01-\d{9}$/){
			push @errors,[$topdir,"ALEPH_ID_NOT_FOUND","No aleph file found, or directory with name of aleph identifier"];
		}
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Grim::Test::Dir);

1;
