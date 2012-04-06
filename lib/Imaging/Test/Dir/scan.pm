package Imaging::Test::Dir::scan;
use Moo;
use ClamAV::Client;

has _scanner => (
	is => 'ro',
	isa => sub {
		instance($_[0],"ClamAV::Client");
	},
	lazy => 1,
	default => sub { ClamAV::Client->new(); }
);

sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my(@errors) = ();
	my %results = ();
	eval{
		%results = $self->_scanner->scan_path_complete(abs_path($topdir));
	};
	if($@){
		push @errors,[$topdir,"ANTIVIRUS_SCAN_FAILED",$@];
	};
	while(my($path,$result)=each %results){
		push @errors,[$path,"ANTIVIRUS_SCAN_NOT_PASSED","$result"];
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Imaging::Test::Dir);

1;
