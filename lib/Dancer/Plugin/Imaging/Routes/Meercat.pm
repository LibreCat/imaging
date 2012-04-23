package Dancer::Plugin::Imaging::Routes::Meercat;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Try::Tiny;
use WebService::Solr;

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
sub marcxml2baginfo {
    my $xml = shift;

    use XML::XPath;
    use POSIX qw(strftime);

    my $xpath = XML::XPath->new(xml => $xml);
    my $rec = {};
    my @fields = qw(
        DC-Title DC-Identifier DC-Description DC-DateAccepted DC-Type DC-Creator DC-AccessRights DC-Subject
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

    #push(@{$rec->{'DC-DateAccepted'}}, strftime("%Y-%m-%d",localtime));

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

    return $rec;
}
sub str_clean {
    my $str = shift;
    $str =~ s/\n//gom;
    $str =~ s/^\s//go;
    $str =~ s/\s$//go;
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

sub meercat {
    state $meercat = WebService::Solr->new(
        config->{'index'}->{meercat}->{url},{default_params => {wt => 'json'}}
    );
}

register meercat => \&meercat;
register marcxml2baginfo => \&marcxml2baginfo;
register_plugin;

__PACKAGE__;
