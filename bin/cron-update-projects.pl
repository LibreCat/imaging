#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Catmandu::Sane;
use Catmandu qw(:load);
use Dancer qw(:script);
use Catmandu::Util qw(:is :array);
use File::Basename qw();
use File::Spec;
use Try::Tiny;
use Time::HiRes;
use Imaging::Meercat qw(:all);
use Imaging qw(:all);
use Imaging::Util qw(:lock);
use File::Temp qw(tempfile);

my $pidfile;
INIT {
   
  #voer niet uit wanneer andere instantie draait!
  $pidfile = "/tmp/imaging-update-projects.pid";
  acquire_lock($pidfile);
  my $pidfile_register = "/tmp/imaging-register.pid";
  check_lock($pidfile_register);

}
END {
  #verwijder lock
  release_lock($pidfile) if $pidfile && -f $pidfile;
}

#variabelen
my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;


#haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "updating list scans for projects";
my @project_ids = ();
projects()->each(sub{ 
  push @project_ids,$_[0]->{_id}; 
});

foreach my $project_id(@project_ids){

  my $project = projects()->get($project_id);

  my $query = $project->{query};
  next if !$query;

  my @list = ();

  my $meercat = meercat();

  #no searcher for meercat: 'fq' is not implemented by Catmandu::Searchable
  my($offset,$limit,$total) = (0,1000,0);

  my $fetch_successfull = 1;
  try{
    do{

      my $res = $meercat->search(query => $query,fq => 'source:rug01',start => $offset,limit => $limit);
      $total = $res->total;

      foreach my $hit(@{ $res->hits }){
        my $ref = from_xml($hit->{fXML},ForceArray => 1);

        #zoek items in Z30 3, en nummering in Z30 h
        my @items = ();

        foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
          if($marc_datafield->{tag} eq "Z30"){
            my $item = {
              source => $hit->{source},
              fSYS => $hit->{fSYS}
            };
            foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
              if($marc_subfield->{code} eq "3"){
                $item->{"location"} = $marc_subfield->{content};
              }
              if($marc_subfield->{code} eq "h" && $marc_subfield->{content} =~ /^V\.\s+(\d+)$/o){
                $item->{"number"} = $1;
              }
            }
            say "\t".join(',',values %$item);
            push @items,$item;
          }
        }
        push @list,@items;
      }

      $offset += $limit;

    }while($offset < $total);

  }catch{
    $fetch_successfull = 0;
    say STDERR $_;
  };
  if($fetch_successfull){
    say "storing new object list to database";
    $project->{list} = \@list;
    $project->{datetime_last_modified} = Time::HiRes::time;
    projects()->add($project);
    project2index($project);
  }
};
{
  my($success,$error) = index_project->commit;   
  die(join('',@$error)) if !$success;
}
#release memory
@project_ids = ();


#ken scans toe aan projects
say "assigning scans to projects";
my($fh,$filename) = tempfile(UNLINK => 1);
die("could not create temporary file\n") unless $fh;
binmode($fh,":utf8");
say "writing all ids to temporary file $filename";

scans->each(sub{ 
  say $fh $_[0]->{_id} if !-f $_[0]->{path}."/__FIXME.txt";
});

close $fh;

open $fh,"<:utf8",$filename or die($!);

while(my $scan_id = <$fh>){
  chomp $scan_id;
  my $scan = scans->get($scan_id);
  my $result = index_project->search(query => "list:\"".$scan->{_id}."\"");
  if($result->total > 0){        
    my @p_ids = map { $_->{_id} } @{ $result->hits };
    $scan->{project_id} = \@p_ids;
    say "assigning project $_ to scan ".$scan->{_id} foreach(@p_ids);
  }else{
    $scan->{project_id} = [];
  }    
  scans->add($scan);
  scan2index($scan);
}

close $fh;

{
  my($success,$error) = index_scan->commit;   
  die(join('',@$error)) if !$success;
}

say "$this_file ended at ".local_time;
