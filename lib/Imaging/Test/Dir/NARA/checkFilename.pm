package Imaging::Test::Dir::NARA::checkFilename;
use Moo;

has _re_filename => (
	is => 'ro',
	default => sub{
		qr/^([\w_\-]+)_(\d{4})_(\d{4})_(MA|ST)\.([a-zA-Z]+)$/;
	}
);
sub test {
	my $self = shift;
	my $topdir = $self->dir();
	my $file_info = $self->file_info();
	my(@errors) = ();
	my $type_numbers = {};
	my $missing_type_numbers = {};

	#zit er wel iets in?
	if(scalar(@$file_info)<=0){

		push @errors,"$topdir is empty";

	}

	#check lijst op alles dat op MA of ST eindigt
	foreach my $stats(@$file_info){

		next if !$self->is_valid_basename($stats->{basename});

		if($stats->{basename} !~ $self->_re_filename()){

			push @errors,$stats->{path}." does not confirm to required format <directory>_<year>_<sequence>_<type>.<extension>";

		}elsif($1 ne basename($stats->{dirname})){

			push @errors,$stats->{path}." does not include the directory in its path";

		}else{

			#{ MA => [1,2,3,4], ST => [1,2,3] }
			$type_numbers->{$4} ||= [];
			push @{ $type_numbers->{$4} },int($3);

		}
	}

    my $num_st = scalar(@{ $type_numbers->{ST} || [] });
    #indien een ST, dan minstens twee
    if($num_st  > 0 && $num_st < 2){
        push @errors,"when stitch files are present, the minimum number should be 2, not $num_st";
    }

	#check volgorde binnen MA, ST
	foreach my $type(keys %$type_numbers){
		my $numbers = $type_numbers->{$type};
		$numbers = [ sort { $a <=> $b } @$numbers ];
		my @missing_numbers = ();
		for(my $i = 0;$i<scalar(@$numbers);$i++){
			if($i > 0){
				if($numbers->[$i - 1] != ($numbers->[$i] - 1)){
					my $start = $numbers->[$i - 1] + 1;
					my $end = $numbers->[$i] - 1;
					push @missing_numbers,($start..$end);
				}
			}
		}
		$missing_type_numbers->{$type} = \@missing_numbers;
	}

	#check minstens 1 master (en die moet 0001 zijn) -> want vorige kan dat niet controleren!
	my $num_ma = scalar(@{ $type_numbers->{MA} || [] });
	if($num_ma == 0){
		push @errors,"at least one master has to be present, none given";
	}elsif($num_ma == 1 && $type_numbers->{MA}->[0] != 1){
		push @errors,"one master present that does not start from 0001";
	}

	foreach my $type(keys %$missing_type_numbers){
		my $missing = $missing_type_numbers->{$type};
		if(scalar(@$missing)>0){
			push @errors,"directory $topdir is missing $type-files with these sequence numbers:".join(',',@$missing);
		}

	}

	scalar(@errors) == 0,\@errors;
}	

with qw(Imaging::Test::Dir);

1;