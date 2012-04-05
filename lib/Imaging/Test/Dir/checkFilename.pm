package Grim::Test::Dir::checkFilename;
use Moo;

has _re_filename => (
	is => 'ro',
	default => sub{
		qr/^([\w_\-]+)_(\d{4})_(\d{4})_(MA|AC|ST|LS)\.([a-zA-Z]+)$/;
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

		push @errors,[$topdir,"DIRECTORY_EMPTY","$topdir is empty"];

	}

	#check lijst op alles dat op MA of AC of ST of LS eindigt
	foreach my $stats(@$file_info){

		next if !$self->is_valid_basename($stats->{basename});

		if($stats->{basename} !~ $self->_re_filename()){

			push @errors,[$stats->{path},"FILENAME_INVALID_PATTERN",$stats->{path}." does not confirm to required format <directory>_<year>_<sequence>_<type>.<extension>"];

		}elsif($1 ne basename($stats->{dirname})){

			push @errors,[$stats->{path},"FILENAME_DOES_NOT_INCLUDE_DIRECTORY",$stats->{path}." does not include the directory in its path"];

		}else{

			#{ MA => [1,2,3,4], AC => [1,2,3]
			$type_numbers->{$4} ||= [];
			push @{ $type_numbers->{$4} },int($3);

		}
	}

    my $num_st = scalar(@{ $type_numbers->{ST} || [] });
    #indien een ST, dan minstens twee
    if($num_st  > 0 && $num_st < 2){
        push @errors,[$topdir,"MINIMUM_NUMBER_ST_FILES_LESS_THAN_2","when stitch files are present, the minimum number should be 2, not $num_st"];
    }

	#check volgorde binnen MA, AC, ST en LS
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
	foreach my $type(keys %$missing_type_numbers){
		my $missing = $missing_type_numbers->{$type};
		if(scalar(@$missing)>0){
			push @errors,[$topdir,"MISSING_SEQUENCE_NUMBERS","directory $topdir is missing $type-files with these sequence numbers:".join(',',@$missing)];
		}

	}

	scalar(@errors) == 0,\@errors;
}	

with qw(Grim::Test::Dir);

1;
