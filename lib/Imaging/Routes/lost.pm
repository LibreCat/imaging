package Imaging::Routes::lost;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(index_scan);
use Catmandu::Sane;
use Catmandu;

get('/lost',sub{
  #welke mappen zijn 'incoming*', maar staan blijkbaar niet meer op hun plaats?
  my @missing_scans;
  
  index_scan->searcher(

    query => "status:incoming*",
    limit => 1000

  )->each(sub{

    my $hit = shift;
    push @missing_scans,$hit if !(-d $hit->{path});

  });

  template('lost',{
    missing_scans => \@missing_scans
  });

});

true;
