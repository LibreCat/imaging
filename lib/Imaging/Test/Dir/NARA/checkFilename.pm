package Imaging::Test::Dir::NARA::checkFilename;
use Moo;
use Data::Util qw(:check);

has _re_filename => (
    is => 'ro',
    default => sub{
        qr/^([\w_\-]+)_(\d{4})_(\d{4})_(MA|ST)\.([a-zA-Z]+)$/;
    }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir();
    my $file_info = $self->file_info();
    my(@errors) = ();
    my $type_numbers = {};
    my $missing_type_numbers = {};

    #zit er wel iets in?
    if(scalar(@$file_info)<=0){

        push @errors,"$topdir is een lege map";

    }

    #check lijst op alles dat op MA of ST eindigt
    foreach my $stats(@$file_info){

        next if !$self->is_valid_basename($stats->{basename});

        if($stats->{basename} !~ $self->_re_filename()){
    

            push @errors,"Ongeldige bestandsnaam aangetroffen";
            my $index = rindex($stats->{basename},".");
            my $base = substr($stats->{basename},$index + 1);           
            
            #type (MA|ST)
            my $type = substr($base,-2);
            if(!( is_string($type) && (
                $type eq "MA" || $type eq "ST"
            ))){
                $type = defined($type) ? $type:"";
                push @errors,$stats->{path}." moet MA of ST zijn (gevonden:'$type')";
            }

            #sequentienummer (0001)
            my $number = substr($base,-7,4);
            if(!( 
                is_string($number) &&
                $number !~ /^\d{4}$/o
            )){
                $number = defined($number) ? $number:"";
                push @errors,$stats->{path}." bevat geen sequentienummer met vier karakters (gevonden:'$number')";
            }

            #jaartal
            my $year = substr($base,-12,4);
            if(!(
                is_string($year) && $year =~ /^\d{4}$/o
            )){
                $year = defined($year)? $year:"";
                push @errors,$stats->{path}." bevat geen jaartal met vier karakters (gevonden:'$year')";
            }
  

            push @errors,"Voorbeeld goede bestandsnaam: ".basename($topdir)."_2012_0001_MA.tif";

        }elsif($1 ne basename($stats->{dirname})){

            push @errors,$stats->{path}." mist naam van de hoofdmap als eerste deel van de bestandsnaam (hoofdmap: ".basename($topdir).")";

        }else{

            #{ MA => [1,2,3,4], ST => [1,2,3] }
            $type_numbers->{$4} ||= [];
            push @{ $type_numbers->{$4} },int($3);

        }
    }

    my $num_st = scalar(@{ $type_numbers->{ST} || [] });
    #indien een ST, dan minstens twee
    if($num_st  > 0 && $num_st < 2){
        push @errors,"wanneer er stitch files zijn, dan moeten er minimum 2 zijn. Opgegeven: $num_st";
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
        push @errors,"Er moet tenminste 1 master tif aanwezig zijn. Geen aanwezig.";
    }elsif($num_ma == 1 && $type_numbers->{MA}->[0] != 1){
        push @errors,"Een master tif aangetroffen waarvan het sequentienummer niet begint vanaf 0001";
    }

    foreach my $type(keys %$missing_type_numbers){
        my $missing = $missing_type_numbers->{$type};
        if(scalar(@$missing)>0){
            push @errors,"de hoofdmap $topdir mist $type-files met deze sequentienummers:".join(',',@$missing);
        }

    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
