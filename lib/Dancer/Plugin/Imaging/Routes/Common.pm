package Dancer::Plugin::Imaging::Routes::Common;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use File::Path qw(mkpath);
use Catmandu::Util qw(:is);
use Try::Tiny;

sub simple_search_params {
  my $params = params();
  my $query = is_string($params->{q}) ? $params->{q} : "*";

  my $page = is_natural($params->{page}) && int($params->{page}) > 0 ? int($params->{page}) : 1;
  $params->{page} = $page;
  my $limit = is_natural($params->{num}) && int($params->{num}) > 0 ? int($params->{num}) : 20;
  $params->{num} = $limit;
  my $start = ($page - 1)*$limit;
  my $sort = (is_string($params->{'sort'}) && $params->{'sort'} =~ /^(\w+)\s(asc|desc)$/o) ? $params->{sort} : undef;

  return (query => $query,start => $start,limit => $limit,sort => $sort);
}
sub not_found {
	forward('/not_found',{ requested_path => request->path });
}
sub mount_conf {
  state $mount_conf = do {
    my $config = config;
    my $mc;
    if(
        is_hash_ref($config->{mounts}) && is_hash_ref($config->{mounts}->{directories}) &&
        is_string($config->{mounts}->{directories}->{path})
    ){
      my $topdir = $config->{mounts}->{directories}->{path};
      my $subdirectories = is_hash_ref($config->{mounts}->{directories}->{subdirectories}) ? $config->{mounts}->{directories}->{subdirectories} : {};
      foreach(qw(ready processed)){
          $subdirectories->{$_} = is_string($subdirectories->{$_}) ? $subdirectories->{$_} : $_;
      }
      $mc = {
          path => $topdir,
          subdirectories => $subdirectories
      }
    }else{
      $mc = {
          path => "/tmp",
          subdirectories => {
              "ready" => "ready",
              "processed" => "processed"
          }
      };
    }
    $mc;
  };
}
sub mount {
    state $mount = mount_conf->{path};
}
sub subdirectories {
    state $subdirectories = mount_conf->{subdirectories};
}
sub sanity_check {
    my @errors = ();
    try{
        my $mount = mount();
        my $subdirectories = subdirectories();
        -d $mount || mkpath($mount);
        foreach(keys %$subdirectories){
            my $sub = "$mount/".$subdirectories->{$_};
            mkpath($sub) if !-d $sub;
			if(!-w $sub){
				push @errors,"systeem heeft geen schrijfrechten op map $_ ";
			}
        }
    }catch{
        push @errors,$_;
    };
    scalar(@errors)==0,\@errors;
}
sub json {
  to_json($_[0],{ pretty => params()->{pretty} ? 1 : 0 });
}


register mount_conf => \&mount_conf;
register mount => \&mount;
register subdirectories => \&subdirectories;
register sanity_check => \&sanity_check;
register not_found => \&not_found;
register simple_search_params => \&simple_search_params;
register json => \&json;

register_plugin;

true;
