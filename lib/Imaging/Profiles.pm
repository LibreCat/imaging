package Imaging::Profiles;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Moo;
use all qw(Imaging::Profile::*);

has _profile_packages => (
    is => 'ro',
    predicate => "has_profile_packages",
    default => sub {
        my $self = shift;
        my @packages = grep { $_ =~ /^Imaging\/Profile\//o } keys %INC;
        foreach(@packages){ s/\.pm$//o; }
        foreach(@packages){ s/\//::/go; }
        [sort @packages];
    }
);
has _packages => (
    is => 'rw',
    default => sub{ {}; }
);
sub profile {
    my($self,$package_name)=@_;
    $self->_packages->{$package_name} ||= $package_name->new;
}

sub get_profile {
    my($self,$dir)=@_;
    foreach my $package_name(@{ $self->_profile_packages }){
        my $ref = $self->profile($package_name);
        if($ref->test($dir)){ 
            $package_name =~ s/Imaging::Profile:://g;
            return $package_name; 
        }
    }
    return undef;
}

__PACKAGE__;
