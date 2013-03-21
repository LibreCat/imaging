package Imaging::Routes::qa_control;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use List::MoreUtils qw(first_index);

hook before => sub {

  if(request->path_info =~ /^\/qa_control/o){
    if(!(auth->asa('admin') || auth->asa('qa_manager'))){

      request->path_info('/access_denied');
      params->{text} = "U mist de nodige gebruikersrechten om deze pagina te kunnen zien";
      
    }
  }
};

get('/qa_control',sub {

  my $params = params;
  my $config = config;
  my @errors = ();
  my $index_scan = index_scan();
  my $q = is_string($params->{q}) ? $params->{q} : "*";

  my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
  $params->{page} = $page;
  my $num = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
  $params->{num} = $num;
  my $offset = ($page - 1)*$num;
  my $sort = $params->{sort};

  my $result;
  my @states = @{ $config->{status}->{collection}->{qa_control} || [] };
  my $fq = join(' OR ',map { "status:$_" } @states);

  my $facet_status;
  my $total_qa_control = 0;
  #facets opvragen over de hele index
  try{
    $result = index_scan->search(
      query => "*:*",
      fq => $fq,
      facet => "true",
      "facet.field" => "status",
      limit => 0
    );
    $facet_status = $result->{facets}->{facet_fields}->{status} || [];
    $total_qa_control = $result->total;
  }catch{
    push @errors,"ongeldige zoekvraag";
  };

  #zoekresultaten ophalen
  my %opts = (
    query => $q,
    fq => $fq,
    start => $offset,
    limit => $num,
    reify => scans()
  );

  if($sort =~ /^\w+\s(?:asc|desc)$/o){
    $opts{sort} = $sort;
  }else{
    $opts{sort} = $config->{app}->{qa_control}->{default_sort} if $config->{app}->{qa_control} && $config->{app}->{qa_control}->{default_sort};
  }

  my $hits = [];
  try {
    $result= index_scan->search(%opts);
    $hits = $result->hits();
  }catch{
    push @errors,"ongeldige zoekvraag";
  };

  for my $hit(@$hits){
    try{
      $hit->{dir_info} = dir_info($hit->{path});
    }catch{};
  }

  if(scalar(@errors)==0){
    my $page_info = Data::Pageset->new({
      'total_entries'       => $result->total,
      'entries_per_page'    => $num,
      'current_page'        => $page,
      'pages_per_set'       => 8,
      'mode'                => 'fixed'
    });
    template('qa_control',{
      scans => $hits,
      page_info => $page_info,
      facet_status => $facet_status,
      total_qa_control => $total_qa_control
    });
  }else{
    template('qa_control',{
      scans => [],
      errors => \@errors
    });
  }
});

true;
