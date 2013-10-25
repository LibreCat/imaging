package Imaging::Meercat;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use POSIX qw(floor strftime);
use XML::LibXML;
use XML::LibXML::XPathContext;
use Exporter qw(import);
our @EXPORT_OK=qw(size_pretty marc_to_baginfo_dc);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);


our $marc_type_map = {
  'article'        => 'Text' ,
  'audio'          => 'Sound' ,
  'book'           => 'Text' ,
  'coin'           => 'Image' ,
  'cursus'         => 'Text' ,
  'database'       => 'Dataset' ,
  'digital'        => 'Dataset' ,
  'dissertation'   => 'Text' ,
  'ebook'          => 'Text' ,
  'ephemera'       => 'Text' ,
  'film'           => 'MovingImage' ,
  'image'          => 'Image' ,
  'manuscript'     => 'Text' ,
  'map'            => 'Image' ,
  'medal'          => 'Image' ,
  'microform'      => 'Text' ,
  'mixed'          => 'Dataset' ,
  'music'          => 'Sound' ,
  'newspaper'      => 'Text' ,
  'periodical'     => 'Text' ,
  'plan'           => 'Image' ,
  'poster'         => 'Image' ,
  'score'          => 'Text' ,
  'videorecording' => 'MovingImage' ,
  '-'              => 'Text'
};

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

sub size_pretty {
  my $size = shift;
  if(is_natural($size) && $size > 0){
    foreach my $currency(@$currencies){
      my $q = $size / $currency->{size};
      if($q < 1){
          next;
      }else{
          return floor($q)." ".$currency->{name};
      }
    }
  }else{
    return "0 KB";
  }
}
sub marc_to_baginfo_dc {
  my(%opts) = @_;
  my $xml = $opts{xml};
  my $source = $opts{source} || "rug01",
  my $rec = {};

  if(is_string($xml)){
    my $libxml = XML::LibXML->load_xml(string => $xml);
    my $xpath = XML::LibXML::XPathContext->new($libxml);
    my @fields = qw(
        DC-Title DC-Identifier DC-Description DC-DateAccepted DC-Type DC-Creator DC-AccessRights DC-Subject
        Archive-Id
    );
    $rec->{$_} = [] foreach(@fields);

    my $id = &marc_controlfield($xpath,'001');

    push(@{$rec->{'DC-Title'}},uc($source)."-$id");

    push(@{$rec->{'DC-Identifier'}}, "$source:$id");
    for my $val (&marc_datafield_array($xpath,'852','j')){
      push(@{$rec->{'DC-Identifier'}}, $val) if $val =~ /\S/o;
    }
    my $f035 = &marc_datafield($xpath,'035','a');
    push(@{$rec->{'DC-Identifier'}}, $f035) if $f035;

    my $description = &marc_datafield($xpath,'245');
    push(@{$rec->{'DC-Description'}}, $description);

    push(@{$rec->{'DC-DateAccepted'}}, strftime("%Y-%m-%d",localtime));

    my $type = &marc_datafield($xpath,'920','a');
    push(@{$rec->{'DC-Type'}}, $marc_type_map->{$type} || $marc_type_map->{'-'});

    my $creator = &marc_datafield($xpath,'100','a');
    push(@{$rec->{'DC-Creator'}}, $creator) if $creator;

    for my $val (&marc_datafield_array($xpath,'700','a')) {
      push(@{$rec->{'DC-Creator'}}, $val) if $val =~ /\S/;
    }

    my $rights = &marc_datafield($xpath,'856','z');
    if($rights =~ /no access/io){
      push(@{$rec->{'DC-AccessRights'}},'closed');
    }elsif ($rights =~ /ugent/io){
      push(@{$rec->{'DC-AccessRights'}},'ugent');
    }else{
      push(@{$rec->{'DC-AccessRights'}},'open');
    }

    for my $subject (&marc_datafield_array($xpath,'922','a')){
      push(@{$rec->{'DC-Subject'}},$subject) if $subject =~ /\S/;
    }

  }

  return $rec;
}
sub baginfo_bagit_fields {
  my(%opts) = @_;
  my $rec = {};

  #Bagging-Date: YYYY-MM-DD
  $rec->{'Bagging-Date'} = [strftime("%Y-%m-%d",localtime)];

  if(exists $opts{size} && is_natural($opts{size})){

    #Bag-Size: 90 MB
    $rec->{'Bag-Size'} = [size_pretty($opts{size})];

  }
  if(exists $opts{num_files} && is_natural($opts{num_files})){
    #Payload-Oxum: OctetCount.StreamCount
    $rec->{'Payload-Oxum'} = ["$opts{size}.$opts{num_files}"];        
  }

  return $rec;
}
sub str_clean {
  my $str = shift;
  $str =~ s/\n//gom;
  $str =~ s/^\s+//go;	
  $str =~ s/\s+$//go;	
  $str =~ s/\s\s+/ /go;
  $str;
}
sub marc_controlfield {
  my($xpath,$field) = @_;
  my $search = '/marc:record';
  $search .= "/marc:controlfield[\@tag='$field']" if $field;
  return &str_clean($xpath->findvalue($search));
}
sub marc_datafield {
  my($xpath,$field,$subfield) = @_;

  my $search = '/marc:record';
  $search .= "/marc:datafield[\@tag='$field']" if $field;
  $search .= "/marc:subfield[\@code='$subfield']" if $subfield;
  return &str_clean($xpath->findvalue($search));
}
sub marc_datafield_array {
  my($xpath,$field,$subfield) = @_;

  my $search = '/marc:record';
  $search .= "/marc:datafield[\@tag='$field']" if $field;
  $search .= "/marc:subfield[\@code='$subfield']" if $subfield;

  my @vals = ();
  for my $node($xpath->find($search)->get_nodelist) {
    push @vals,$node->textContent;
  }

  return @vals;
}

1;
