package Template::Plugin::SizePretty;
use parent qw(Template::Plugin);
use POSIX qw(floor);

my $currencies =[
{
	name => "TB", size => 1024**4
},
{	
	name => "GB" ,size => 1024**3
},
{
	name => "MB", size => 1024**2,
},
{
	name => "KB", size => 1024
},
{
	name => "B", size => 1
}
];

sub new {
	my ($class, $context) = @_;
	$context->define_vmethod($_, size_pretty => \&size_pretty ) for qw(scalar);		
	bless {}, $class;
}
sub size_pretty {
	my $size = shift;
	my @sizes = ();
    if($size > 0){
        foreach my $currency(@$currencies){
            my $q = $size / $currency->{size};
            if($q < 1){
                next;
            }else{
                return floor($q)." ".$currency->{name};
            }
        }
    }else{
        return "0KB";
    }
}

__PACKAGE__;
=head1 NAME

    Template::Plugin::SizePretty - pretty print file size

=cut
