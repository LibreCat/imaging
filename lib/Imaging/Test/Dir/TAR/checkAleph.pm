package Imaging::Test::Dir::TAR::checkAleph;
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
        my $url = $self->solr_args->{url};
        WebService::Solr->new($url,{ default_params => {wt => "json"} });
    }
);
has _re => (
    is => 'ro',
    default => sub { qr/^RUG01-(\d{9})$/; }
);
sub is_fatal {
    0;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my $basename_topdir = basename($topdir);
    my(@errors) = ();
    my $query = "";


    my $fSYS;
    if($basename_topdir =~ $self->_re){

        $fSYS = $1;

    }else{

        my $lookup_dir = $topdir;
        if(Data::Util::is_string($self->lookup) && $self->lookup ne "."){
            $lookup_dir = Cwd::realpath(File::Spec->catdir($topdir,$self->lookup));
        }
        my @rug01_files = grep { 
            $_ =~ /RUG01-(\d{9})$/o && ($fSYS = $1)
        } glob("$lookup_dir/*");
        my $num_rug01_files = scalar(@rug01_files);

        if($num_rug01_files == 0){

            push @errors,"$basename_topdir: geen rug01-bestand gevonden";

        }elsif($num_rug01_files > 1){

            push @errors,"$basename_topdir: meer dan één rug01-bestand gevonden";

        }
    }
    if(scalar(@errors) == 0 && Data::Util::is_string($fSYS)){

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
