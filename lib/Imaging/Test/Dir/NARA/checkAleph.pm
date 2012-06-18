package Imaging::Test::Dir::NARA::checkAleph;
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
        my $url = $self->solr_args->{url};
        WebService::Solr->new($url,{ default_params => {wt => "json"} });
    }
);
sub is_fatal {
    0;
};

sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my(@errors) = ();
    my $query = basename($topdir);

    if($query =~ /^RUG(\d{2})-(\d{9})$/o){
        $query = "rug$1:$2";
    }

    try{
        my $res = $self->_solr->search($query,{ rows => 0, wt => "json" });
        if($res->content->{response}->{numFound} <= 0){
            push @errors,"$query niet gevonden in Aleph";
        }
    }catch{
        push @errors,$_;
    };

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
