package Dancer::Plugin::Imaging::Routes::Common;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use Catmandu::Util qw(:is);

sub simple_search_params {
  my $params = params();
  params_to_search($params);
}
sub params_to_search {
  my $params = $_[0];
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
sub json {
  to_json($_[0],{ pretty => params()->{pretty} ? 1 : 0 });
}

register not_found => \&not_found;
register simple_search_params => \&simple_search_params;
register params_to_search => \&params_to_search;
register json => \&json;

register_plugin;

true;
