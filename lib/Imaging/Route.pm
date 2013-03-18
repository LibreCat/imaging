package Imaging::Route;
use Dancer ':syntax';
use Catmandu::Sane;
use Dancer::Plugin::Database;

prefix undef;

sub dbi_handle {
  state $dbi_handle = database;
}

hook before => sub {
  my $session = session;
  if($session->{user}){
    my $user = dbi_handle->quick_select('users',{ id => $session->{user}->{id} });
    if($user){
      $session->{user}->{has_dir} = $user->{has_dir};
      session(user => $session->{user}); 
    }
  }
};

any('/not_found',sub{
  status 'not_found';
  header( "refresh" => config->{refresh_rate}."; URL=".uri_for(config->{default_app}) );
  template('not_found',{
      requested_path => uri_for(params->{requested_path})
  });
});
any qr{.*} => sub {
  status 'not_found';
  header( "refresh" => config->{refresh_rate}."; URL=".uri_for(config->{default_app}) );
  template('not_found',{
    requested_path => uri_for(request->path)
  });
};

true;
