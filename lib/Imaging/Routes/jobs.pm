package Imaging::Routes::jobs;
use Dancer ':syntax';
use Catmandu::MediaMosa;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Try::Tiny;
use Dancer::Plugin::Imaging::Routes::Common;

get '/jobs/:asset_id' => sub {

  my $params = params;
  my(@errors,@messages,@hits);
  my $response = {errors => \@errors,messages => \@messages,hits => \@hits};  
  
  try{
    my($offset,$limit,$total)=(0,200,0);
    do{
      
      my $vpcore = mediamosa()->asset_job_list({
        user_id => "Nara",
        asset_id => $params->{asset_id},
        limit => $limit,
        offset => $offset
      });
      if($vpcore->header->request_result() ne "success"){        
        die($vpcore->header->request_result_description()."\n");
      }
      $total = $vpcore->header->item_count_total;
      $vpcore->items->each(sub{
        push @hits,$_[0];
      });

      $offset += $limit;
    }while($offset < $total);   
  }catch{
    push @errors,$_;
  };

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  content_type 'json';  
  return json($response);

};
sub mediamosa {
  state $mediamosa = Catmandu::MediaMosa->new(
     %{ config->{mediamosa}->{rest_api} }
  );
}

true;
