package Dancer::Plugin::Imaging::Routes::Meercat;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use WebService::Solr;
use POSIX qw(floor);
use XML::XPath;

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

sub create_baginfo {
    my(%opts) = @_;
    my $xml = $opts{xml};
    my $size = $opts{size};
    my $num_files = $opts{num_files};
    my $old_bag_info = is_hash_ref($opts{bag_info}) ? $opts{bag_info} : {};

    use XML::XPath;
    use POSIX qw(strftime);

    my $xpath = XML::XPath->new(xml => $xml);
    my $rec = {};
    my @fields = qw(
        DC-Title DC-Identifier DC-Description DC-DateAccepted DC-Type DC-Creator DC-AccessRights DC-Subject
        Archive-Id
    );
    $rec->{$_} = [] foreach(@fields);

    my $id = &marc_controlfield($xpath,'001');

    push(@{$rec->{'DC-Title'}}, "RUG01-$id");

    push(@{$rec->{'DC-Identifier'}}, "rug01:$id");
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
    if ($rights =~ /no access/io) {
        push(@{$rec->{'DC-AccessRights'}}, 'closed');
    }
    elsif ($rights =~ /ugent/io) {
        push(@{$rec->{'DC-AccessRights'}}, 'ugent');
    }
    else {
        push(@{$rec->{'DC-AccessRights'}}, 'open');
    }

    for my $subject (&marc_datafield_array($xpath,'922','a')) {
		push(@{$rec->{'DC-Subject'}}, $subject) if $subject =~ /\S/;
    }

    #bagit fields:

    #Bagging-Date: YYYY-MM-DD
    $rec->{'Bagging-Date'} = [strftime("%Y-%m-%d",localtime)];

    #Bag-Size: 90 MB
    $rec->{'Bag-Size'} = [size_pretty($size)];

    #Payload-Oxum: OctetCount.StreamCount
    $rec->{'Payload-Oxum'} = ["$size.$num_files"];

    #merge result with old bag-info
    $rec = { %$old_bag_info,%$rec };
    
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
    my $xpath = shift;
    my $field = shift;

    my $search = '/marc:record';
    $search .= "/marc:controlfield[\@tag='$field']" if $field;
    return &str_clean($xpath->findvalue($search)->to_literal->value);
}
sub marc_datafield {
    my $xpath = shift;
    my $field = shift;
    my $subfield = shift;

    my $search = '/marc:record';
    $search .= "/marc:datafield[\@tag='$field']" if $field;
    $search .= "/marc:subfield[\@code='$subfield']" if $subfield;
    return &str_clean($xpath->findvalue($search)->to_literal->value);
}
sub marc_datafield_array {
    my $xpath = shift;
    my $field = shift;
    my $subfield = shift;

    my $search = '/marc:record';
    $search .= "/marc:datafield[\@tag='$field']" if $field;
    $search .= "/marc:subfield[\@code='$subfield']" if $subfield;

    my @vals = ();
    for my $node ($xpath->find($search)->get_nodelist) {
      push @vals , $node->string_value;
    }

    return @vals;
}

sub marcxml2marc {
   my $record = shift;

   return unless $record =~ m{\S+};

   $record =~ s/<marc:/</g;
   $record =~ s/<\/marc:/<\//g;
   my $xpath  = XML::XPath->new(xml => $record);
   my $id = $xpath->findvalue('/record/controlfield[@tag=\'001\']')->value();

   say "$id FMT   L BK";
   my $leader = $xpath->findvalue('/record/leader')->value();
   $leader =~ s/ /^/g;
   say "$id LDR   L $leader";
   foreach my $cntrl ($xpath->find('/record/controlfield')->get_nodelist) {
        my $tag   = $cntrl->findvalue('@tag')->value();
        my $value = $cntrl->findvalue('.')->value();
        say "$id $tag   L $value";
   }
   foreach my $data ($xpath->find('/record/datafield')->get_nodelist) {
        my $tag   = $data->findvalue('@tag')->value();
        my $ind1  = $data->findvalue('@ind1')->value();
        my $ind2  = $data->findvalue('@ind2')->value();

        $ind1 = is_string($ind1) ? $ind1 : " ";
        $ind2 = is_string($ind2) ? $ind2 : " ";

        my @subf = ();
        foreach my $subf ($data->find('.//subfield')->get_nodelist) {
          my $code  = $subf->findvalue('@code')->value();
          my $value = $subf->findvalue('.')->value();
          push(@subf,"\$\$$code$value");
        }

        my $value = join "" , @subf;
        say "$id $tag$ind1$ind2 L $value";
   }
}
sub meercat {
    state $meercat = WebService::Solr->new(
        config->{'index'}->{meercat}->{url},{
            default_params => {
                %{ config->{'index'}->{meercat}->{default_params} },
                wt => 'json'
            }
        }
    );
}

register meercat => \&meercat;
register create_baginfo => \&create_baginfo;
register_plugin;

__PACKAGE__;
