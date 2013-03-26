package Template::Plugin::Merge;
use parent qw(Template::Plugin);
use Hash::Merge qw(merge);

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub new {
  my ($class, $context) = @_;
  $context->define_vmethod($_, merge => \&_merge ) for qw(hash);    
  bless {}, $class;
}
sub _merge {
  my $merge = {};
  $merge = merge($merge,$_) for(@_);
  $merge;
}

__PACKAGE__;
