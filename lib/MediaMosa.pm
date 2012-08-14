package MediaMosa;
use Catmandu::Sane;
use Moo;
use LWP::UserAgent;
use Data::UUID;
use Data::Util qw(:check :validate);
use Digest::SHA1 qw(sha1_hex);
use MediaMosa::Response;
use URI::Escape;

#zie http://www.mediamosa.org/sites/default/files/Webservices-MediaMosa-1.5.3.pdf

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

sub _ua {
    state $_ua = LWP::UserAgent->new(
        cookie_jar => {}
    );
}
sub _validate_web_response {
    my $res = shift;
    $res->is_error && confess($res->content."\n");
}
sub _parse_vp_response {
    my $res = shift;
    _validate_web_response($res);    
    MediaMosa::Response::parse($res->content);
}
sub _validate_vp_response {
    my $res = shift;    
    my $vp = _parse_vp_response($res);
    $vp->header->request_result eq "success" or confess($vp->header->request_result_description."\n");
    $vp;
}
sub vp_request {
    my($self,@args) = @_;
    $self->login;
    $self->_vp_request(@args);
}
sub _vp_request {
    my($self,$path,$params,$method)=@_;
    $method ||= "GET";
    my $res;
    if(uc($method) eq "GET"){
        $res = $self->_get($path,$params);
    }elsif(uc($method) eq "POST"){
        $res = $self->_post($path,$params);
    }else{
        confess "method $method not supported";
    }
    my $vp = _validate_vp_response($res);
}
sub _construct_params_as_array {
    my $params = shift;
    my @array = ();
    for my $key(keys %$params){
        if(is_array_ref($params->{$key})){
            #PHP only recognizes 'arrays' when their keys are appended by '[]' (yuk!)
            for my $val(@{ $params->{$key} }){
                push @array,$key."[]" => $val;
            }
        }else{
            push @array,$key => $params->{$key};
        }
    }
    return \@array;
}
sub _post {
    my($self,$path,$data)=@_;
    $self->_ua->post($self->base_url.$path,_construct_params_as_array($data));
}
sub _construct_query {
    my $data = shift;
    my @parts = ();
    for my $key(keys %$data){
        if(is_array_ref($data->{$key})){
            for my $val(@{ $data->{$key} }){
                push @parts,URI::Escape::uri_escape($key)."=".URI::Escape::uri_escape($val);
            }
        }else{
            push @parts,URI::Escape::uri_escape($key)."=".URI::Escape::uri_escape($data->{$key});
        }
    }
    join("&",@parts);
}
sub _get {
    my($self,$path,$data)=@_;
    my $query = _construct_query($data) || "";
    $self->_ua->get($self->base_url.$path."?$query");
}
sub _authenticate {
    my $self = shift;
    #dbus communication

    #client: EGA stuurt "AUTH DBUS_COOKIE_SHA1 <username>" naar VP-Core
    my $vp = $self->_vp_request("/login",{
        dbus => "AUTH DBUS_COOKIE_SHA1 ".$self->user
    },"POST");

    #server: "DATA vpx 0 <challenge-server>"
    my $answer1 = $vp->items->item->[0]->{dbus};
    #say $answer1;
    if($answer1 !~ /^DATA vpx 0 ([a-f0-9]{32})$/o){
        confess("invalid dbus response from server: $answer1\n");
    }
    my $challenge_server = $1;

    #client: EGA verzint willekeurige tekst <random> 
    #   en berekent response string: 
    #   <response> = sha1(<challenge-server>:<random>:<password>)
    my $random = Data::UUID->new->create_str;

    #client: EGA stuurt "DATA <random> <response>" naar VP-Core
    my $response_string = sha1_hex("$challenge_server:$random:".$self->password);
    $vp = $self->_vp_request("/login",{
        dbus => "DATA $random $response_string"
    },"POST");

    my $answer2 =  $vp->items->item->[0]->{dbus};  
    #say $answer2;

    #server: OK|REJECTED vpx
    if($answer2 !~ /^(OK|REJECTED) (\w+)$/o){
        confess("invalid dbus response from server: $answer2\n");
    }    
    my $success = $1;
    return $success eq "OK";
}
sub login {
    my $self = shift;
    state $logged_in = 0;
    $logged_in ||= $self->_authenticate();
}

#assets
sub asset_create {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/create",$params,"POST");
}
sub asset_delete {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/create",$params,"POST");
}
sub asset_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset",$params,"GET");
}
sub asset {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}",$params,"GET");
}
sub asset_update {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}",$params,"POST");
}
sub asset_play {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/play",$params,"GET");
}
sub asset_still {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/still",$params,"GET");
}
sub asset_still_create {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/still/create",$params,"POST");
}
sub asset_job_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/joblist",$params,"GET");
}
sub asset_collection_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/collection",$params,"GET");
}
sub asset_metadata_update {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/metadata",$params,"POST");
}
sub asset_mediafile_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/asset/$params->{asset_id}/mediafile",$params,"GET");
}

#jobs
sub job_status {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/job/$params->{job_id}/status",$params,"GET");
}
sub job_delete {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/job/$params->{job_id}/delete",$params,"POST");
}
#collections
sub collection_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/collection",$params,"GET");
}
sub collection {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/collection/$params->{coll_id}",$params,"GET");
}
sub collection_asset_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/collection/$params->{coll_id}/asset",$params,"GET");
}
sub collection_create {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/collection/create",$params,"POST");
}

#trancode
sub transcode_profile_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/transcode/profiles",$params,"GET");
}
sub preview_profile_id {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/preview_profile_id",$params,"GET");
}

#mediafile
sub mediafile_create {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/mediafile/create",$params,"POST");
}
sub mediafile {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/mediafile/$params->{mediafile_id}",$params,"POST");
}
sub mediafile_update {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/mediafile/$params->{mediafile_id}",$params,"POST");
}
sub mediafile_upload_ticket_create {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/mediafile/$params->{mediafile_id}/uploadticket/create",$params,"POST");
}
sub mediafile_transcode {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/mediafile/$params->{mediafile_id}/transcode",$params,"POST");
}

#user
sub user_job_list {
    my($self,$params) = @_;
    $params ||= {};
    $self->vp_request("/user/$params->{owner_id}/joblist",$params,"GET");
}


=head1 NAME
    
    MediaMosa - Perl connector for the MediaMosa REST API

=head1 SYNOPSIS

    my $mm = MediaMosa->new( user => "foo",password => "mysecret" );

    #login is handled automatically ;-), and only redone when the session cookie expires
    #$mm->login;
    
    #equivalent of /asset?offset=0&limit=100
    my $vpcore = $mm->asset_list({ offset => 0,limit => 1000});

    say "total found:".$vp->header->item_count_total;
    say "total fetched:".$vp->header->item_count;

    #the result list 'items' is iterable!
    $vpcore->items->each(sub{
        my $item = shift;
        say "asset_id:".$item->{asset_id};
    });

=head1 DESCRIPTION

    A implementation of Grim::Acl must contain a method 'is_allowed'. This method
    compares the information in the request environment with information in the
    media-record, and returns true when allowed.

=cut

__PACKAGE__;
