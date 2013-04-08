package Imaging::Routes::jobs;
use Dancer ':syntax';
use Catmandu::MediaMosa;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Try::Tiny;

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
        my $jobs = $_[0];
        for my $id(keys %$jobs){
          push @hits,$jobs->{$id};          
        }
      });

      $offset += $limit;
    }while($offset < $total);   
  }catch{
    push @errors,$_;
  };

  $response->{status} = scalar(@errors) == 0 ? "ok":"error";

  content_type 'json';  
  return to_json($response);

};
sub mediamosa {
  state $mediamosa = Catmandu::MediaMosa->new(
     %{ config->{mediamosa}->{rest_api} }
  );
}

true;
