package Imaging::Routes::status;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu::Util qw(:is);

get('/status',sub {

  my $params = params;
  my @users;
  my $mount_conf = mount_conf;    

  users->each(sub{
    my $user = $_[0];
    my $ready = mount()."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login};
    push @users,$_[0] if -d $ready;
  });
  my $stats = {
    fixme => {},
    ready => {},
  };
  my $config = config;

  #aantal directories in 01_ready
  my $mount_ready = mount()."/".$mount_conf->{subdirectories}->{ready};
  foreach my $user(@users){
    my $dir_ready = $mount_ready."/".$user->{login};
    my @files = glob("$dir_ready/*");
    $stats->{ready}->{$user->{login}} = scalar(@files);
    $stats->{fixme}->{$user->{login}} = 0;
    for(@files){
      if(-f "$_/__FIXME.txt"){
        $stats->{fixme}->{$user->{login}}++;
      }
    }
  }

  #status facet
  my $result = index_scan->search(
    query => "*",
    limit => 0,
    facet => "true",
    "facet.field" => "status"
  );
  my(%facet_counts) = @{ $result->{facets}->{facet_fields}->{status} ||= [] };
  my @states = @{ $config->{status}->{collection}->{status_page} || [] };
  my $facet_status = {};
  foreach my $status(@states){
    $facet_status->{$status} = $facet_counts{$status} || 0;
  }

  #ontbrekende scans
  my $missing = {};
  index_scan->searcher(

    query => "status:incoming*",
    limit => 1000

  )->each(sub{

    my $hit = shift;
    if( !(-d $hit->{path}) ){
      $missing->{ $hit->{user_login} }++;
    }

  });

  template('status',{
    missing => $missing,
    stats => $stats,
    facet_status => $facet_status
  });

});

true;
