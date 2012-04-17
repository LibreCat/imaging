package Imaging::Test::Dir::checkAleph;
use Moo;
use WebService::Solr;
use Data::Util qw(:validate);
use Try::Tiny;

has solr_args => (
	is => 'ro',
	isa => sub{ hash_ref($_[0]); },
	default => sub {
		{};
	}
);
has _solr => (
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		print Dumper($self->solr_args);
		my $url = delete $self->solr_args->{url};
		WebService::Solr->new($url,{ default_params => {wt => "json"} });
	}
);

sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my(@errors) = ();

	try{
		my $res = $self->_solr->search(basename($topdir),{ rows => 0, wt => "json" });
		if($res->content->{response}->{numFound} <= 0){
			push @errors,basename($topdir)." not found in Aleph";
		}
	}catch{
		push @errors,$_;
	};

	scalar(@errors) == 0,\@errors;
}	

with qw(Imaging::Test::Dir);

1;
