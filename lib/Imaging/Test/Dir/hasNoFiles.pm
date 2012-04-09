package Imaging::Test::Dir::hasNoFiles;
use Moo;
use Data::Util qw(:check :validate);

has patterns => (
	is => 'rw',
	isa => sub {
		my $array = shift;		
		array_ref($array);
		foreach(@$array){
            if(!is_rx($_)){
                $_ = qr/$_/;
            }
        }
		rx($_) foreach(@$array);
	},
	lazy => 1,
	default => sub{
		[];
	}
);
sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();

	foreach my $pattern(@{ $self->patterns }){
		my $found;
		foreach my $stats(@$file_info){
			$found = $stats if $stats->{basename} =~ $pattern;
		}
		if($found){
			push @errors,"forbidden file ".$found->{path}." found in $topdir";
		}
	}
	scalar(@errors) == 0,\@errors;
}	

with qw(Imaging::Test::Dir);

1;
