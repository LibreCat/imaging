package Template::Plugin::Merge;
use parent qw(Template::Plugin);
use Hash::Merge qw(merge);

#Hash::Merge::specify_behavior({
#  "SCALAR" => {
#    "SCALAR" => sub { $_[1] },
#    "ARRAY"  => sub { [ $_[0], @{$_[1]} ] },
#    "HASH"   => sub { $_[1] },
#  },
#  "ARRAY" => {
#    "SCALAR" => sub { $_[1] },
#    "ARRAY"  => sub { [ @{$_[0]}, @{$_[1]} ] },
#    "HASH"   => sub { $_[1] }, 
#  },
#  "HASH" => {
#    'SCALAR' => sub { $_[1] },
#    'ARRAY'  => sub { [ values %{$_[0]}, @{$_[1]} ] },
#    'HASH'   => sub { Hash::Merge::_merge_hashes( $_[0], $_[1] ) }, 
#  }
#});
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
