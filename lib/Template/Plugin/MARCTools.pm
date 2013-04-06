package Template::Plugin::MARCTools;
use parent qw(Template::Plugin);
use POSIX qw(floor);
use XML::LibXML;
use XML::LibXML::XPathContext;

sub new {
  my ($class, $context) = @_;
  $context->define_vmethod($_, xml_to_aleph_sequential => \&xml_to_aleph_sequential ) for qw(scalar);   
  bless {}, $class;
}
sub xml_to_aleph_sequential {
  my $xml = $_[0];
  $xml =~ s/(\n|\r)//g;

  my @data = ();
  return \@data unless $xml =~ m{\S+};

  $xml =~ s/<marc:/</g;
  $xml =~ s/<\/marc:/<\//g;
  
  my $libxml = XML::LibXML->load_xml(string => $xml);
  my $xpath = XML::LibXML::XPathContext->new($libxml);

  my $id = $xpath->findvalue('/record/controlfield[@tag=\'001\']');

  push @data,[$id,"FMT","","","L",["BK"]];

  my $leader = $xpath->findvalue('/record/leader');
  $leader =~ s/ /^/g;
  push @data,[$id,"LDR","","","L",[$leader]];
  foreach my $cntrl ($xpath->find('/record/controlfield')->get_nodelist) {
    my $tag   = $cntrl->findvalue('@tag');
    my $value = $cntrl->findvalue('.');
    push @data,[$id,$tag,"","","L",[$value]];
  }
  foreach my $data ($xpath->find('/record/datafield')->get_nodelist) {
    my $tag   = $data->findvalue('@tag');
    my $ind1  = $data->findvalue('@ind1');
    my $ind2  = $data->findvalue('@ind2');

    my @subf = ();
    foreach my $subf ($data->find('.//subfield')->get_nodelist) {
      my $code  = $subf->findvalue('@code');
      my $value = $subf->findvalue('.');
      push @subf,$code,$value;
    }

    my $value = join "" , @subf;
    push @data,[$id,$tag,$ind1,$ind2,"L",\@subf];
  }
  return \@data;
}

1;
=head1 NAME

    Template::Plugin::MARC - convert marcxml to aleph sequential
    [
        [
            "001357509",
            "tag-1",
            "ind1",
            "ind-2",
            [
                "a",
                "data-a",
                "b",
                "data-b"
            ]
        ]
    ]

=cut
