#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer qw(:script);
use Catmandu qw(store);
use Dancer::Plugin::Database;
use Catmandu::Util qw(require_package :is :array);
use Catmandu::Sane;
use File::Basename qw();
use Cwd qw(abs_path);
use Data::Dumper;
use Imaging qw(:all);
use Clone qw(clone);

BEGIN {
  #load configuration
  my $appdir = Cwd::realpath(
      dirname(dirname(
          Cwd::realpath( __FILE__)
      ))
  );
  Dancer::Config::setting(appdir => $appdir);
  Dancer::Config::setting(public => "$appdir/public");
  Dancer::Config::setting(confdir => $appdir);
  Dancer::Config::setting(envdir => "$appdir/environments");
  Dancer::Config::load();
  Catmandu->load($appdir);
}

sub to_index {
  my $scan = shift;       

  #default doc
  my $doc = clone($scan);

  #metadata
  my @metadata_ids = ();
  push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} }); 
  $doc->{metadata_id} = \@metadata_ids;
  $doc->{marc} = [];
  push @{ $doc->{marc} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});

  #status history
  for(my $i = 0;$i < scalar(@{ $scan->{status_history} });$i++){
      my $item = $scan->{status_history}->[$i];
      $doc->{status_history}->[$i] = $item->{user_login}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
  }

  #project info
  delete $doc->{project_id};
  if(is_array_ref($scan->{project_id}) && scalar(@{$scan->{project_id}}) > 0){
      foreach my $project_id(@{$scan->{project_id}}){
          my $project = projects->get($project_id);
          next if !is_hash_ref($project);
          foreach my $key(keys %$project){
              next if $key eq "list";
              my $subkey = "project_$key";
              $subkey =~ s/_{2,}/_/go;
              $doc->{$subkey} ||= [];
              push @{$doc->{$subkey}},$project->{$key};
          }
      }
  }

  #user info
  if($scan->{user_id}){
    my $user = store("core")->bag("users2")->get($scan->{user_id});
    if($user){
      my @keys = qw(name login roles);
      $doc->{"user_$_"} = $user->{$_} foreach(@keys);
    }
  }
  
  #convert datetime to iso
  foreach my $key(keys %$doc){
      next if $key !~ /datetime/o;
      if(is_array_ref($doc->{$key})){
          $_ = formatted_date($_) for(@{ $doc->{$key} });
      }else{
          $doc->{$key} = formatted_date($doc->{$key});
      }
  }

  #opkuisen
  my @deletes = qw(metadata comments busy warnings new_path new_user publication_id);
  delete $doc->{$_} for(@deletes);

  index_scan()->add($doc);

}

my @users = database->quick_select("users",{});
my $bag = store("core")->bag('users2');

say "users => users2";
foreach my $user(@users){
  say "\t".$user->{id}." => ".$user->{login};
  $user->{_id} = $user->{login};
  delete $user->{id};
  $user->{roles} = [ map { $_ =~ s/^\s+|\s+$//; $_  } split /\,/, $user->{roles} ];
  $bag->add($user);
}
say "change attribute user_id in scans";
index_scan->each(sub{
  my $hit = $_[0];
  say $hit->{_id};
  my $scan = scans->get($hit->{_id});
  my $old_user = database->quick_select("users",{ id => $scan->{user_id} });
  say "\t".$old_user->{id}." => ".$old_user->{login};
  $scan->{user_id} = $old_user->{login};
  scans->add($scan);
});
say "reindexing scans";
scans->each(sub{
  say "\t".$_[0]->{_id};
  to_index($_[0]);
});
index_scan->commit;
