package MediaMosa;
use Catmandu::Sane;
use Moo;
use LWP::UserAgent;
use Data::UUID;
use XML::Simple;
use Data::Util qw(:check :validate);
use Digest::SHA1 qw(sha1_hex);

has base_url => (
    is => 'ro',
    required => 1
);
has user => (
    is => 'ro',
    required => 1
);
has password => (
    is => 'ro',
    required => 1
);
has ua => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        LWP::UserAgent->new(
            cookie_jar => {}
        );
    }
);
has xml_parser => (
    is => 'ro',
    lazy => 1,
    default => sub {
        XML::Simple->new;
    }
);
sub from_xml {
    my($self,$data) = @_;
    $self->xml_parser->XMLin($data,ForceArray=>1);
}
sub get_hash_response {
    my($self,$res)=@_;
    $res->is_error && confess($res->content);
    my $hash = $self->from_xml($res->content);
    array_ref($hash->{header}) && array_ref($hash->{items});
    if($hash->{header}->[0]->{request_result}->[0] ne "success"){
        confess $hash->{header}->[0]->{request_result_description}->[0];
    }
    $hash;
}
sub authenticate {
    my $self = shift;
    #dbus communication
    my $res = $self->ua->post($self->base_url."/login",{
        dbus => "AUTH DBUS_COOKIE_SHA1 ".$self->user
    });
    my $r = $self->get_hash_response($res);
    my $answer1 =  $r->{items}->[0]->{item}->[0]->{dbus}->[0];
    say $answer1;
    if($answer1 !~ /^DATA vpx 0 ([a-f0-9]{52})$/o){
        confess("invalid dbus response from server: $answer1");
    }
    my $challenge_server = $1;
    my $random = Data::UUID->new->create_str;

    my $response_string = sha1_hex("$challenge_server:$random:".$self->password);
    $res = $self->ua->post($self->base_url."/login",{
        dbus => "DATA $random $response_string"
    });
    $r = $self->get_hash_response($res);
    my $answer2 =  $r->{items}->[0]->{item}->[0]->{dbus}->[0];  
    say $answer2;
}


__PACKAGE__;
