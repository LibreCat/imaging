package Imaging::Routes::ids;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Catmandu::Sane;
use Catmandu;
use Try::Tiny;

any('/ids',sub {
    my $params = params;
    
    send_file(
        \"",
        streaming => 1,
        callbacks => {
            override => sub {
                my($respond,$response)=@_;
                my $writer = $respond->(200,"text/plain; charset=utf-8");

                my($start,$total,$limit)=(0,0,100);

                try{
                    do{
                        my $hits = index_scan->search(q => $params->{q},start => $start,limit => $limit);

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
