package Imaging::Routes::archived;
use Dancer ':syntax';
use Catmandu::FedoraCommons;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Try::Tiny;

get '/archive' => sub {

  my $params = params;
  my(@errors,@messages,@hits);
  my $response = {errors => \@errors,messages => \@messages,hits => \@hits};  

  if($params->{token}){
    
    my $r = fedora()->resumeFindObjects(sessionToken => $params->{token});
    my $obj = $r->is_ok ? $r->parse_content : {};
    my $results = $obj->{results} // [];
    $response->{token} = $obj->{token};
    if(@$results){

      push @hits,@$results;

    }else{

      push @errors,"geen resultaten voor token '$params->{token}'";

    }
 
  }
  elsif($params->{query}){

    my $r = fedora()->findObjects(query => $params->{query},maxResults => 10);    
    my $obj = $r->is_ok ? $r->parse_content : {};
    my $results = $obj->{results} // [];
    $response->{token} = $obj->{token};
    if(@$results){

      push @hits,@$results;

    }else{

      push @errors,"geen resultaten voor query '$params->{query}'";

    }
  }else{

    push @errors,"no query or token given";

  }

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  content_type 'json';  
  return to_json($response);

};
sub fedora {
  state $fedora = Catmandu::FedoraCommons->new(@{ config->{fedora}->{args} // [] });
}

true;
