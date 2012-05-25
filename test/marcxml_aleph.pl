#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use XML::XPath;
use open qw(:std :utf8);

local($/);
$/ = undef;
my $content = <STDIN>;
$content =~ s/(\n|\r)//g;
&process_xml($content);

sub process_xml {
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
