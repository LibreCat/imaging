#!/usr/bin/env perl
use Catmandu qw(:load);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);

use Imaging::Meercat qw(:all);
use Imaging qw(:all);
use Imaging::Util qw(:files :data :lock);
use Imaging::Dir::Info;
use Imaging::Bag::Info;

use File::Basename qw();
use all qw(Imaging::Dir::Query::*);

my $pidfile;
INIT {
   
  #voer niet uit wanneer andere instantie draait!
  $pidfile = "/tmp/imaging-update-metadata.pid";
  acquire_lock($pidfile);
  my $pidfile_register = "/tmp/imaging-register.pid";
  check_lock($pidfile_register);

}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}

#variabelen
sub directory_translator_packages {
  state $c = do {
    my $config = Catmandu->config;
    my $list = [];
    if(is_array_ref($config->{directory_to_query})){
      $list = $config->{directory_to_query};
    }
    $list;
  };
}
sub directory_translator {
  state $translators = {};
  my $package = shift;
  $translators->{$package} ||= $package->new;
}
sub directory_to_queries {
  my $path = shift;
  my $packages = directory_translator_packages();    
  my @queries = ();
  foreach my $p(@$packages){
    my $trans = directory_translator($p);
    if($trans->check($path)){
      @queries = $trans->queries($path);
      last;
    }
  }
  if(scalar @queries == 0){
    push @queries,File::Basename::basename($path);
  }
  @queries;
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

#stap 1: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
#
#   1ste metadata-record wordt neergeschreven in bag-info.txt: mediamosa pikt deze metadata op

my @ids_ok_for_metadata = ();
{
  my $query = "-status:\"incoming\" AND -status:\"incoming_error\" AND -status:\"done\"";

  say "retrieving metadata for good scans ($query)";
 
  index_scan->searcher( 

    query => $query,
    limit => 1000

  )->each(sub{
    
    my $doc = shift;
    #reify in searcher werkt nog niet..
    my $scan = scans()->get($doc->{_id});

    if(
      !(is_array_ref($scan->{metadata}) && scalar(@{ $scan->{metadata} }) > 0 ) &&
      !(-f $scan->{path}."/__FIXME.txt")
    ){
      push @ids_ok_for_metadata,$scan->{_id};
    }

  });

}

foreach my $id(@ids_ok_for_metadata){
  my $scan = scans()->get($id);
  my $path = $scan->{path};
  my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});

  #parse hash indien bag-info.txt bestaat, en indien niet, maak nieuwe aan
  my $baginfo_path = $scan->{path}."/bag-info.txt";
  my $baginfo;
  if(-f $baginfo_path){
    $baginfo = Imaging::Bag::Info->new(source => $baginfo_path)->hash;
  }

  #haal metadata op
  my @queries = directory_to_queries($path);

  foreach my $query(@queries){
    my $res = meercat()->search(query => $query,fq => 'source:rug01');
    $scan->{metadata} = [];
    if($res->total > 0){

      for my $hit(@{ $res->hits }){              

        push @{ $scan->{metadata} },{
          fSYS => $hit->{fSYS},#000000001
          source => $hit->{source},#rug01
          fXML => $hit->{fXML},
          baginfo => defined($baginfo) ? $baginfo : marc_to_baginfo_dc(xml => $hit->{fXML})
        };

      }
      last;
    }

  }
  my $num = scalar(@{$scan->{metadata}});
  say "\tscan ".$scan->{_id}." has $num metadata-records";

  update_scan($scan);
}

say "$this_file ended at ".local_time;
