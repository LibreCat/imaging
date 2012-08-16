package Imaging::Routes::external;
use Dancer ':syntax';
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu;
use Data::Util qw(:check :validate);
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);
use LWP::UserAgent;


hook before => sub {
    if(request->path =~ /^\/external/o){
        if(!authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }
    }
};
sub array_contains {
    my($array,$val) = @_;
    (first_index { $_ eq $val } @$array) >= 0;
}
sub construct_query {
    my $data = shift;
    my @parts = ();
    for my $key(keys %$data){
        if(is_array_ref($data->{$key})){
            for my $val(@{ $data->{$key} }){
                push @parts,uri_escape($key)."=".uri_escape($val);
            }
        }else{
            push @parts,uri_escape($key)."=".uri_escape($data->{$key});
        }
    }
    join("&",@parts);
}
sub ua {
    state $lwp = LWP::UserAgent->new( cookie_jar => {}, ssl_opts => { verify_hostname => 0 } );
}

my $apps = ["grep","grim"];

any('/external',sub {
    my $params = params;
    my $config = config;

    my @messages = ();
    my @errors = ();
    
    my $res = { status => "error", errors => \@errors, messages => \@messages };

    my $app_id = $params->{app_id};

    if(!is_string($app_id)){
        push @errors,"parameter \"app_id\" is missing";
        status '400';
        content_type 'json';
        return to_json($res);
    }elsif(!array_contains($apps,$app_id)){        
        push @errors,"invalid app_id";
        status '400';
        content_type 'json';
        return to_json($res);
    }

    delete $params->{app_id};
    my $url;

    if($app_id eq "grim"){
        $url = config->{$app_id}->{base_url}."/rest?".construct_query($params);
    }elsif($app_id eq "grep"){
        $url = config->{$app_id}->{base_url}."/app/api?".construct_query($params);    
    }

    my $external_res = ua->get($url);
    status $external_res->code;
    content_type $external_res->content_type;
    return $external_res->content;
});

true;
