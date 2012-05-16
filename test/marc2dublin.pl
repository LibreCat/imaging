#!/usr/bin/env perl
use Dancer qw(:script);
use Catmandu qw(store);
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is);
use Cwd;
use Try::Tiny;
use Time::HiRes;
use File::Temp qw(tempfile);
use IO::Handle;
BEGIN {
    my $appdir = Cwd::realpath("..");
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}
use Dancer::Plugin::Imaging::Routes::Utils;

use Catmandu::Importer::MARC;
use Catmandu::Fix;
use Data::Dumper;

my $fix_file = config->{appdir}."/".Catmandu->config->{fix_files}->{marc2dublincore};
-f $fix_file || die("$fix_file does not exist\n");
my $fixer = Catmandu::Fix->new(fixes => [$fix_file]);

my $scans = scans();
$scans->each(sub{
    my $scan = shift;
    foreach my $metadata(@{ $scan->{metadata} || [] }){
        my $xml = $metadata->{fXML};
        $xml =~ s/[\n\r]//go;       
        open my $fh,"<",\$xml or die($!);
        my $importer = Catmandu::Importer::MARC->new(file => $fh, type => 'XML');
        $fixer->fix($importer)->each(sub{
            my $ref = shift;
            foreach(keys %$ref){
                if(is_array_ref($ref->{$_})){
                    delete $ref->{$_} if scalar(@{ $ref->{$_} }) <= 0;
                }
            }
            foreach my $key(sort keys %$ref){
                if(is_array_ref($ref->{$key})){
                    printf("%20s : %s\n",$key,$_) foreach(@{ $ref->{$key} });
                }else{

                }
            }
        });
        close $fh;
    }
});
