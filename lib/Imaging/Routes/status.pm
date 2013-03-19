package Imaging::Routes::status;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Dancer::Plugin::Auth::RBAC;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);
use Data::Pageset;
use Try::Tiny;
use URI::Escape qw(uri_escape);

hook before => sub {
  if(request->path_info =~ /^\/status/o){
    if(!authd){
      my $service = uri_escape(uri_for(request->path_info));
      return redirect(uri_for("/login")."?service=$service");
    }
  }
};
hook before_template_render => sub {
  my $tokens = $_[0];
  $tokens->{auth} = auth();
};
any('/status',sub {

  my $params = params;
  my @users;
  users->each(sub{
    push @users,$_[0] if $_[0]->{has_dir};
  });
  my $mount_conf = mount_conf;    
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
  template('status',{
    stats => $stats,
    facet_status => $facet_status
  });

});

true;
