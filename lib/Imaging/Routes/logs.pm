package Imaging::Routes::logs;
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

hook before => sub {
    if(request->path =~ /^\/logs/o){
        if(!authd){
            my $service = uri_escape(uri_for(request->path));
            return redirect(uri_for("/login")."?service=$service");
        }
    }
};
any('/logs',sub {
    my $params = params;
    my $index_log = index_log();
    my $q = is_string($params->{q}) ? $params->{q} : "*";

    my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
    $params->{page} = $page;
    my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
    $params->{num} = $num;
    my $offset = ($page - 1)*$num;
    my $sort = $params->{sort};

    my %opts = (
        query => $q,
        start => $offset,
        limit => $num
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
    }else{
        $opts{sort} = ["datetime desc","scan_id desc"];
    }
    my($result,$error);
    try {
        $result= index_log->search(%opts);
    }catch{
        $error = $_;
    };
    if(!$error){
        my $page_info = Data::Pageset->new({
            'total_entries'       => $result->total,
            'entries_per_page'    => $num,
            'current_page'        => $page,
            'pages_per_set'       => 8,
            'mode'                => 'fixed'
        });
        template('logs',{
            logs => $result->hits,
            page_info => $page_info,
            auth => auth()
        });
    }else{
        template('logs',{
            logs => [],
            error => $error,
            auth => auth()
        });
    }
});

true;
