package Bottom;
use parent qw(Top);

sub catfiles { File::Spec->catfile( @_ ) }

1;
