package Imaging::Routes::Control::First;
use Dancer ':syntax';
use Catmandu::Sane;
use Dancer::Plugin::Auth::RBAC;
use URI::Escape qw(uri_escape);

hook before => sub {

  #onthoud laatste zoekparameters
  if(request->path =~ /^\/(scans|logs|projects|qa_control)$/o){     
    my $app = $1;
    my $params = params();    
    remember_search_params($app);
    #gebruik parameters indien niets meegegeven (remember_search_params slaat enkel op indien iets opgegeven)
    set_last_search_params($app);  
  }

  if(request->path !~ /^\/(login|logout)/o && !authd){

    my $service = uri_escape(uri_for(request->path));
    return redirect(uri_for("/login")."?service=$service");
    
  }
};

sub remember_search_params {
  my $app = shift;
  my $params = params();
  for my $name(qw(q sort num)){
    session("last_${app}_${name}" => $params->{$name}) if exists $params->{$name};
  }
}
sub set_last_search_params {
  my $app = shift;
  my $params = params();
  for my $name(qw(q sort num)){
    $params->{$name} = session("last_${app}_${name}") unless exists $params->{$name};
  }
}

true;
