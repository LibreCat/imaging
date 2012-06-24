package Imaging::Test::Dir::TAR::checkAleph;
use Moo;
use WebService::Solr;
use Try::Tiny;
use Data::Util qw(:check :validate);
use File::Basename;
use File::Spec;

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
        my $default_params = $self->solr_args->{default_params};
        WebService::Solr->new($url,{ default_params => {
            %$default_params,
            rows => 0, 
            wt => "json"
        } });
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
    my $topdir = $self->dir_info->dir();
    my $basename_topdir = basename($topdir);
    my(@errors) = ();
    my $query = "";


    my $fSYS;
    if($basename_topdir =~ $self->_re){

        $fSYS = $1;

    }else{

        my @rug01_files = grep { 
            $_ =~ /RUG01-(\d{9})$/o && ($fSYS = $1)
        } glob("$topdir/*");
        my $num_rug01_files = scalar(@rug01_files);

        if($num_rug01_files == 0){

            push @errors,"$basename_topdir: geen rug01-bestand gevonden";

        }elsif($num_rug01_files > 1){

            push @errors,"$basename_topdir: meer dan één rug01-bestand gevonden";

        }
    }
    if(scalar(@errors) == 0 && is_string($fSYS)){

        $query = "rug01:$fSYS";
        try{
            my $res = $self->_solr->search($query,{});
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
