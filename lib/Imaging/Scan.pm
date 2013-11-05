package Imaging::Scan;
use Catmandu qw(:load);
use Catmandu::Sane;
use Catmandu::Util qw(:is);

use Imaging::Util qw(:files);
use Imaging qw(:all);

use File::Basename;
use File::Copy qw(copy move);
use File::Path qw(mkpath rmtree);
use Try::Tiny;
use English '-no_match_vars';

use Exporter qw(import);
our @EXPORT_OK = qw(return_scan sync_baginfo);
our %EXPORT_TAGS = (
  all => \@EXPORT_OK,
);

sub return_scan {
  my $scan = shift;
  my $new_path = $scan->{new_path};

  #is de operatie gezond?
  if(!(
      is_string($scan->{path}) && -d $scan->{path}
  )){

    my $p = $scan->{path} || "";
    return "Cannot move from 02_processed: scan directory '$p' does not exist";

  }elsif(!is_string($new_path)){

    return "Cannot move from $scan->{path} to '': new_path is empty";

  }elsif(! -d dirname($new_path) ){

    return "Will not move from $scan->{path} to $new_path: parent directory of $new_path does not exist";

  }elsif(-d $new_path){

    return "Will not move from $scan->{path} to $new_path: directory already exists";

  }elsif(!( 
      -w dirname($scan->{path}) &&
      -w $scan->{path})
  ){

    return "Cannot move from $scan->{path} to $new_path: system has no write permissions to $scan->{path} or its parent directory";

  }elsif(! -w dirname($new_path) ){
    
    return "Cannot move from $scan->{path} to $new_path: system has no write permissions to parent directory of $new_path";

  }


  #gebruiker bestaat?
  my $login;
  if($scan->{new_user}){
    $login = $scan->{new_user};
  }else{
    my $user = users->get( $scan->{user_id} );
    $login = $user->{login};
  }

#  my($user_name,$pass,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire)=getpwnam($login);
#  if(!is_string($uid)){
#    say STDERR "$login is not a valid system user!";
#    return;
#  }elsif($uid == 0){
#    say STDERR "root is not allowed as user";
#    return;
#  }
#  my $group_name = getgrgid($gid);
  my $user_name = $login;
  my $this_gid = getgrgid($EGID);
  my $group_name = $this_gid;

  my $old_path = $scan->{path};    
  my $manifest = "$old_path/__MANIFEST-MD5.txt";
 
  say "$old_path => $new_path";

  local(*FILE);

  #maak directory en plaats __FIXME.txt
  mkpath($new_path);
  #plaats __FIXME.txt
  my $log = get_log($scan);
  open FILE,">$new_path/__FIXME.txt" or return complain($!);
  print FILE $log->{status_history}->[-1]->{comments};
  close FILE;

 
  #verplaats bestanden die opgelijst staan in __MANIFEST-MD5.txt naar 01_ready
  #andere bestanden laat je staan (en worden dus verwijderd)
  open FILE,$manifest or return complain($!);
  while(my $line = <FILE>){
  
    $line =~ s/\r\n$/\n/;
    chomp($line);
    utf8::decode($line);
    my($checksum,$filename)=split(/\s+/o,$line);

    mkpath(File::Basename::dirname("$new_path/$filename"));   
    say "moving $old_path/$filename to $new_path/$filename";
    if(
        !move("$old_path/$filename","$new_path/$filename")
    ){
      return "could not move $old_path/$filename to $new_path/$filename";
    }
    say "moving $old_path/$filename to $new_path/$filename successfull";

  }
  close FILE; 
  
  #gelukt! verwijder nu oude map
  rmtree($old_path);
  
  #pas paden aan
  $scan->{path} = $new_path;

  #stel nieuwe gebruiker in
  #$scan->{user_id} = $scan->{new_user};

  #update databank en index
 
  ($scan,$log) = set_status($scan,status => "incoming");

  #gedaan ermee
  delete $scan->{$_} for(qw(busy new_path new_user asset_id));

  update_log($log,-1);
  update_scan($scan);

  my @errors;
  #done? rechten aanpassen aan dat van 01_ready submap
  #775 zodat imaging achteraf de map terug in processed kan verplaatsen!
  try{
    `sudo chown -R $user_name:$group_name $scan->{path} && sudo chmod -R 775 $scan->{path}`;
  }catch{
    push @errors,$_;
  };

  @errors;
}

=head2 SYNOPSIS

  1.  lees bag-info.txt in in variabele $baginfo
        indien leeg initialiseer met metadata uit $scan->{metadata}
  2.  zit 'Archive-Id' in de $baginfo?
        ja:   update $scan->{archive_id}
        nee:  maak nieuwe archive_id aan, en sla die op in $scan->{archive_id} en
              in $baginfo->{'Archive-Id'} = [$archive-id]
  3.  kopiëer $baginfo naar ALLE metadata elementen
  4.  schrijf $baginfo naar bag-info.txt

  return $archive_id,0|1 (is new?)

=cut
sub sync_baginfo {
  my $scan = $_[0];
  
  my $archive_id_new = 0;

  my $baginfo = {};
  my $path_baginfo = $scan->{path}."/bag-info.txt";

  #poging 1: lees bag-info.txt
  if(-f $path_baginfo){
    $baginfo = Imaging::Bag::Info->new(source => $path_baginfo)->hash;
  }
  #poging 1 mislukt (bestand leeg of niet bestaande), maar wel opgehaalde metadata?
  if(keys %$baginfo == 0 && scalar(@{ $scan->{metadata} })){
    $baginfo = $scan->{metadata}->[0]->{baginfo};
  }

  #inspecteer of 'Archive-Id' erin zit
  if(
    is_array_ref($baginfo->{'Archive-Id'}) && scalar(@{ $baginfo->{'Archive-Id'} }) > 0
  ){

    $scan->{archive_id} = $baginfo->{'Archive-Id'}->[0];    

  }else{

    $scan->{archive_id} = "archive.ugent.be:".Data::UUID->new->create_str;
    $baginfo->{'Archive-Id'} = [ $scan->{archive_id} ];
    $archive_id_new = 1;

  }

  #stel alles nu in metadata in
  if(scalar(@{ $scan->{metadata} })){
    $_->{baginfo} = $baginfo for @{$scan->{metadata}};
  }

  write_to_baginfo($path_baginfo,$baginfo);

  return $scan->{archive_id},$archive_id_new;
}


1;
