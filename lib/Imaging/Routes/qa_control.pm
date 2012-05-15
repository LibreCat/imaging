package Imaging::Routes::qa_control;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);
use List::MoreUtils qw(first_index);

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
    my $index_scan = index_scan();
    my $q = is_string($params->{q}) ? $params->{q} : "*";

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;
    my $sort = $params->{sort};

    my @states = qw(registered derivatives_created archived published);
    my $fq = join(' OR ',map {
        "status:$_"
    } @states);
    my %opts = (
        query => $q,
        fq => $fq,
        start => $offset,
        limit => $num,
        facet => "true",
        "facet.field" => "status"
    );
    if(is_string($sort)){
        $opts{sort} = [ $sort ] if $sort =~ /^\w+\s(?:asc|desc)$/o;
    }elsif(is_array_ref($sort)){
        my $ok = 1;
        foreach(@$sort){
            if($_ !~ /^\w+\s(?:asc|desc)$/o){
                $ok = 0;
                last;
            }
        }
        if($ok){
            $opts{sort} = $sort;
        }
    }
    my @errors = ();
    my($result);
    try {
        $result= index_scan->search(%opts);
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
            scans => $result->hits,
            page_info => $page_info,
            auth => auth(),
            facet_status => $result->{facets}->{facet_fields}->{status} || [],
            mount_conf => mount_conf()
        });
    }else{
        template('qa_control',{
            scans => [],
            errors => \@errors,
            auth => auth(),
            mount_conf => mount_conf()
        });
    }
});

true;
