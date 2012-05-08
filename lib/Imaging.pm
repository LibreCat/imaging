package Imaging;
our $VERSION = "0.01";
use Catmandu::Sane;
use Catmandu qw(:load config);
use Data::Util qw(:check);

sub store_conf_valid {

    my $name = shift;
    is_hash_ref(config->{store}) && is_hash_ref(config->{store}->{$name}) && is_hash_ref(config->{store}->{$name}->{options}) && is_string(config->{store}->{$name}->{package});

}

__PACKAGE__;
