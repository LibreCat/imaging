package Imaging::Dir::Query::BAG;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Imaging::Bag::Info;
use File::Basename;
use Try::Tiny;
use Moo;

sub check {
  my($self,$path) = @_;
  defined $path && -d $path && -f "$path/bag-info.txt";
}
sub queries {    
  my($self,$path) = @_;
  return () if !defined($path);
  my $path_baginfo = "$path/bag-info.txt";
  my @queries = ();
  try{
    #parse bag-info.txt
    my $parser = Imaging::Bag::Info->new(source => $path_baginfo);
    my $baginfo = $parser->hash;
    #haal (goede) queries op
    if(is_array_ref($baginfo->{'Archive-Id'}) && scalar(@{ $baginfo->{'Archive-Id'} }) > 0){
  
      #archive_id is mogelijks nieuw gemaakt door Imaging, en bestaat nog niet in Meercat
      @queries = "\"".$baginfo->{'Archive-Id'}->[0]."\" OR ".basename($path);

    }else{

      @queries = @{$baginfo->{'DC-Identifier'}};
      my @filter = ();
      foreach(@queries){
        if(/^rug01:\d{9}$/o){
          @filter = $_;
          last;
        }else{
          push @filter,$_;
        }
      }
      @queries = @filter;

    }
  };
  @queries;
}   

with qw(Imaging::Dir::Query);

1;
