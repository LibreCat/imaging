package Imaging::Routes::qa_control;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);

sub core {
    state $core = store("core");
}
sub indexer {
    state $index = store("index")->bag("locations");
}
sub facet_status {
    my(%opts) = @_;
    $opts{q} ||= "*:*";
    $opts{fq} ||= "*:*";
    $opts{q} = "($opts{q}) AND _bag:locations";
    $opts{fq} = "($opts{fq}) AND _bag:locations";
    my $index = indexer->store->solr;
    my $facet_status;
    try{
        my $res = $index->search($opts{q},{ fq => $opts{fq}, rows => 0,facet => "true","facet.field" => "status" });
        $facet_status = $res->facet_counts->{facet_fields}->{status} || [];
    }catch{
        $facet_status = [];
    };
    $facet_status;
}
sub locations {
    state $locations = core()->bag("locations");
}

hook before => sub {
    if(request->path =~ /^\/qa_control/o){
        if(!authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }
    }
};
any('/qa_control',sub {

    if(!(auth->asa('admin') || auth->asa('qa_manager'))){
        return forward('/access_denied',{
            text => "U mist de nodige gebruikersrechten om deze pagina te kunnen zien"
        });
    }

    my $params = params;
    my $indexer = indexer();
    my $q = is_string($params->{q}) ? $params->{q} : "*";

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;
    my $sort = $params->{sort};

    my @states = qw(registered derivatives_created reprocess_scans reprocess_metadata reprocess_derivatives archived);
    my $fq = join(' OR ',map {
        "status:$_"
    } @states);
    say $fq;
    my %opts = (
        query => $q,
        fq => $fq,
        start => $offset,
        limit => $num
    );
    $opts{sort} = $sort if $sort && $sort =~ /^\w+\s(?:asc|desc)$/o;
    my @errors = ();
    my($result);
    try {
        $result= indexer->search(%opts);
    }catch{
        push @errors,"ongeldige zoekvraag";
    };
    if(scalar(@errors)==0){
        my $page_info = Data::Pageset->new({
            'total_entries'       => $result->total,
            'entries_per_page'    => $num,
            'current_page'        => $page,
            'pages_per_set'       => 8,
            'mode'                => 'fixed'
        });
        template('qa_control',{
            locations => $result->hits,
            page_info => $page_info,
            auth => auth(),
            facet_status => facet_status($q,$fq),
            mount_conf => mount_conf()
        });
    }else{
        template('qa_control',{
            locations => [],
            errors => \@errors,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});

true;
