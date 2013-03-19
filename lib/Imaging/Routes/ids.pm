package Imaging::Routes::ids;
use Dancer ':syntax';
use Imaging qw(index_scan);
use Catmandu::Sane;
use Catmandu;
use Try::Tiny;

get('/ids',sub {
  my $params = params;
  
  send_file(
    \"",
    streaming => 1,
    callbacks => {
      override => sub {
        my($respond,$response)=@_;
        my $writer = $respond->([200,["Content-Type" => "text/plain; charset=utf-8"]]);

        my($start,$total,$limit)=(0,0,100);

        try{
          do{
            my $hits = index_scan->search(query => $params->{q},start => $start,limit => $limit);

            for my $hit(@{ $hits->hits() }){
              $writer->write($hit->{_id}."\n");
            }
     
            $total = $hits->total;
            $start += $limit;
       
          }while($start < $total);
        }catch{
          $writer->write($_);        
        }
      }
    }
  );
});

true;
