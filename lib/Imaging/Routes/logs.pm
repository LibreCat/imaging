package Imaging::Routes::logs;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(index_log);
use Catmandu::Sane;
use Try::Tiny;

get('/logs',sub {

  my $config = config;
  my $index_log = index_log();

  my %opts = simple_search_params();
  $opts{sort} = $config->{app}->{logs}->{default_sort} if !defined($opts{sort}) && $config->{app}->{logs} && $config->{app}->{logs}->{default_sort};

  my($result,$error);
  try {
    $result= index_log->search(%opts);
  }catch{
    $error = $_;
  };

  template('logs',{
    result => $result,
    error => $error          
  });

});

true;
