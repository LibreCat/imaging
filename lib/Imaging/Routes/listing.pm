package Imaging::Routes::listing;
use Dancer ':syntax';
use Dancer::Plugin::Imaging::Routes::Common;
use Imaging qw(:all);
use Catmandu::Sane;
use Catmandu;
use Catmandu::Util qw(:is);
use Try::Tiny;
use File::Find;

get('/ready/:user_login',sub{
  my $params = params;
  my $user = users->get( $params->{user_login} );
  $user or return not_found();
  
  my $mount = mount();
  my $subdirectories = subdirectories();
  my $dir = "$mount/".$subdirectories->{ready}."/".$user->{login};
 
  #voor welke mappen bestaat een record? 
  my @directories;
  if(-d $dir){

    local(*DIR);
    opendir DIR,$dir;
    while(my $file = readdir(DIR)){

      next if $file eq "." || $file eq "..";
      my $path = "$dir/$file";
      next if !-d $path;

      my $dir_info = dir_info($path);
      my $obj = {
        name => $file,
        info => $dir_info,
        record => scans()->get($file)
      };
      push @directories,$obj;

    }
    closedir(DIR);    
    
  }

  template('ready',{
    directories => \@directories,
    user => $user
  });

});
get('/ready/:user_login/:scan_id',sub{
  my $params = params;
  my $mount_conf = mount_conf();

  #user bestaat
  my $user = users->get( $params->{user_login} );
  $user or return not_found();

  #directory bestaat
  my $scan_id = $params->{scan_id};
  my $path = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{ready}."/".$user->{login}."/$scan_id";
  -d $path or return not_found();

  my @errors = ();

  #controleer op conflict
  my $has_conflict = 0;
  my $scan = scans()->get($scan_id);
  my($files,$size) = list_files($path);
  if($scan && $scan->{path} ne $path){
    $has_conflict = 1;
    my $other_user = users->get( $scan->{user_id} );
    push @errors,"$scan->{_id} werd eerst bij gebruiker $other_user->{login} aangetroffen.Deze map zal daarom niet verwerkt worden.";
  }

  template('ready/view',{
    scan_id => $scan_id,
    scan => $scan,
    has_conflict => $has_conflict,
    path => $path,
    files => $files,
    size => $size,
    user => $user,
    errors => \@errors      
  });
});

true;
