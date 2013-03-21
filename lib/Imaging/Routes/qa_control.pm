package Imaging::Routes::qa_control;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
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

  my $result;

  #facets opvragen over de hele index
  my @states = @{ $config->{status}->{collection}->{qa_control} || [] };
  my $fq = join(' OR ',map { "status:$_" } @states);
  my $facet_status;
  my $total_qa_control = 0;
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
  my %opts = (simple_search_params(),fq => $fq,reify => scans);
  $opts{sort} = $config->{app}->{qa_control}->{default_sort} if !defined($opts{sort}) && $config->{app}->{qa_control} && $config->{app}->{qa_control}->{default_sort};
  
  try {
    $result= index_scan->search(%opts);    
  }catch{
    push @errors,"ongeldige zoekvraag";
  };

  for my $hit(@{ $result->hits // [] }){
    try{
      $hit->{dir_info} = dir_info($hit->{path});
    }catch{};
  }

  template('qa_control',{
    result => $result,
    facet_status => $facet_status,
    total_qa_control => $total_qa_control
  });

});

true;
