package Imaging::Test::Dir::NARA::checkFilename;
use Moo;
use Catmandu::Sane;
use Data::Util qw(:check :validate);
use Catmandu::Util qw(:array);
use File::Basename;

has types => (
    is => 'ro',
    isa => sub { array_ref($_[0]); },
    lazy => 1,
    default => sub{
        [qw(MA ST)];
    },
    coerce => sub {
        ( is_array_ref($_[0]) && scalar(@{ $_[0] }) > 0 ) ? $_[0] : [qw(MA ST)];
    }
);
has _re_filename => (
    is => 'ro',
    lazy => 1,
    default => sub{
        my $self = shift;
        my $types_join = join('|',@{$self->types()});
        qr/^([\w_\-]+)_(\d{4})_(\d{4})_($types_join)\.([a-zA-Z]+)$/;
    }
);
sub is_fatal {
    1;
};
sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my $files = $self->dir_info->files();
    my $directories = $self->dir_info->directories();
    my(@errors) = ();
    my $type_numbers = {};
    my $missing_type_numbers = {};
    my $types_join = join(',',@{$self->types()});

    #zit er wel iets in?
    if(scalar(@$files) <= 0 && scalar(@$directories) <= 0){

        push @errors,"Deze map is leeg";

    }

    #check lijst op alles dat op MA of ST eindigt
    foreach my $stats(@$files){
        next if !$self->is_valid_basename($stats->{basename});

        if($stats->{basename} !~ $self->_re_filename()){
    
            my $index = rindex($stats->{basename},".");
            if($index >= 0){
                my $base = substr($stats->{basename},0,$index);

                #type
                my $type = substr($base,-2);
                if(!( 
                    is_string($type) &&
                    array_includes($self->types,$type)
                )){
                    $type = defined($type) ? $type:"";
                    push @errors,$stats->{basename}." moet $types_join zijn (gevonden:'$type')";
                }

                #sequentienummer (0001)
                if(length($base) >= 7){
                    my $number = substr($base,-7,4);
                    if(!(
                        is_string($number) &&
                        $number =~ /^\d{4}$/o
                    )){
                        $number = defined($number) ? $number:"";
                        push @errors,$stats->{basename}." moet een sequentienummer met vier karakters bevatten (gevonden:'$number')";
                    }
                }else{
                    push @errors,$stats->{basename}." moet een sequentienummer met vier karakters bevatten (gevonden:'')";
                }

                #jaartal
                if(length($base) >= 12){
                    my $year = substr($base,-12,4);
                    if(!(
                        is_string($year) && $year =~ /^\d{4}$/o
                    )){
                        $year = defined($year)? $year:"";
                        push @errors,$stats->{basename}." moet een jaartal met vier karakters bevatten (gevonden:'$year')";
                    }
                }else{
                    push @errors,$stats->{basename}." moet een jaartal met vier karakters bevatten (gevonden:'')";
                }

            }

            push @errors,"Voorbeeld goede bestandsnaam: ".basename($topdir)."_2012_0001_MA.tif";

        }elsif($1 ne basename($topdir)){

            push @errors,$stats->{basename}." mist naam van de hoofdmap als eerste deel van de bestandsnaam (hoofdmap: ".basename($topdir).")";

        }else{

            #{ MA => [1,2,3,4], ST => [1,2,3] }
            $type_numbers->{$4} ||= [];
            push @{ $type_numbers->{$4} },int($3);

        }
    }

    if(array_includes($self->types,"ST")){
        my $num_st = scalar(@{ $type_numbers->{ST} || [] });
        #indien een ST, dan minstens twee
        if($num_st  > 0 && $num_st < 2){
            push @errors,"wanneer er files zijn van het type ST, dan moeten er minimum 2 zijn. Opgegeven: $num_st";
        }
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

    if(array_includes($self->types,"MA")){
        #check minstens 1 master (en die moet 0001 zijn) -> want vorige kan dat niet controleren!
        my $num_ma = scalar(@{ $type_numbers->{MA} || [] });
        if($num_ma == 0){
            push @errors,"Er moet tenminste 1 master tif aanwezig zijn. Geen aanwezig.";
        }elsif($num_ma == 1 && $type_numbers->{MA}->[0] != 1){
            push @errors,"1 master tif aangetroffen, maar het sequentienummer begint niet met '0001'";
        }
    }

    foreach my $type(keys %$missing_type_numbers){
        my $missing = $missing_type_numbers->{$type};
        if(scalar(@$missing)>0){
            push @errors,"de hoofdmap ".basename($topdir)." mist $type-files met deze sequentienummers:".join(',',@$missing);
        }

    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
