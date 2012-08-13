package MediaMosa::Response;
use Catmandu::Sane;
use Moo;
use XML::Simple;
use Data::Util qw(:check :validate);

sub _xml_parser {
    state $xml_parser = XML::Simple->new;
}
sub _from_xml {
    my($data,%opts) = @_;   
    _xml_parser->XMLin($data,%opts);
}
sub parse {
    my $xml = shift;
    my $ref = _from_xml($xml);
    hash_ref($ref->{header}) && hash_ref($ref->{items});    

    my $header = MediaMosa::Response::Header->new(
        item_count => $ref->{header}->{item_count},
        item_count_total => $ref->{header}->{item_count_total},
        item_offset => $ref->{header}->{item_offset},
        request_process_time => $ref->{header}->{request_process_time},
        request_result => $ref->{header}->{request_result},
        request_result_description => $ref->{header}->{request_result_description},
        request_result_id => $ref->{header}->{request_result_id},
        request_uri => $ref->{header}->{request_uri},
        vpx_version => $ref->{header}->{vpx_version}
    );
    my $items = MediaMosa::Response::Items->new(
        item => is_array_ref($ref->{items}->{item}) ? 

            $ref->{items}->{item} : 

            ( defined($ref->{items}->{item}) ? [$ref->{items}->{item}] : [])
    );
    MediaMosa::Response->new(
        header => $header,
        items => $items
    );
}

has header => (
    is => 'ro',
    isa => sub {
        instance($_[0],"MediaMosa::Response::Header");
    }
);
has items => (
    is => 'ro',
    isa => sub {
        instance($_[0],"MediaMosa::Response::Items");
    }
);

package MediaMosa::Response::Header;
use Catmandu::Sane;
use Moo;
use Data::Util qw(:check :validate);

has item_count => (is => 'ro',required => 1);
has item_count_total => (is => 'ro',required => 1);
has item_offset => (is => 'ro',required => 1);
has request_process_time => (is => 'ro',required => 1);
has request_result => (is => 'ro',required => 1);
has request_result_description => (is => 'ro',required => 1);
has request_result_id => (is => 'ro',required => 1);
has request_uri => (is => 'ro',required => 1);
has vpx_version => (is => 'ro',required => 1);

package MediaMosa::Response::Items;
use Catmandu::Sane;
use Moo;
use Data::Util qw(:check :validate);

has item => (
    is => 'ro',isa => sub{
        my $item = $_[0];
        array_ref($item);
        for(@$item){
            hash_ref($_);
        }        
    }
);

sub generator {
    my $self = shift;
    my $sub = sub {
        state $i = 0;
        if($i < scalar(@{ $self->item })){
            return $self->item->[$i++];
        }else{
            return undef;
        }
    };
    return $sub;   
}

with('Catmandu::Iterable');

__PACKAGE__;
