package Imaging::Test::Dir::BAG::checkAleph;
use Moo;
use WebService::Solr;
use Try::Tiny;

has solr_args => (
    is => 'ro',
    isa => sub{ Data::Util::hash_ref($_[0]); },
    default => sub {
        {};
    }
);
has _solr => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $url = delete $self->solr_args->{url};
        WebService::Solr->new($url,{ default_params => {wt => "json"} });
    }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my(@errors) = ();
    my $query = "";
    my $lookup_dir = $topdir;

    if(Data::Util::is_string($self->lookup) && $self->lookup ne "."){
        $lookup_dir = Cwd::realpath(File::Spec->catdir($topdir,$self->lookup));
    }

    my $fSYS;
    my @rug01_files = grep { 
        $_ =~ /RUG01-(\d{9})$/o && ($fSYS = $1)
    } glob("$lookup_dir/*");
    my $num_rug01_files = scalar(@rug01_files);

    if($num_rug01_files == 0){

        push @errors,basename($topdir).": geen rug01-bestand gevonden";

    }elsif($num_rug01_files > 1){

        push @errors,basename($topdir).": meer dan één rug01-bestand gevonden";

    }else{

        $query = "rug01:$fSYS";

        try{
            my $res = $self->_solr->search($query,{ rows => 0, wt => "json" });
            if($res->content->{response}->{numFound} <= 0){
                push @errors,"$query leverde geen resultaten op in Aleph";
            }
        }catch{
            push @errors,$_;
        };

    }
    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
