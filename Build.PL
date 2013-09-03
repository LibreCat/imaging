use warnings;
use strict;
use Module::Build;

my $requires = {
	perl => '>=5.10.0',
	Dancer => '>=1.3091',
	Plack => '>=0.9985',
  all => 0,
  Catmandu => 0,
  'Catmandu::MARC' => 0,
  'Catmandu::Store::DBI' => 0,
  'Catmandu::Store::Solr' => 0,
  'DBD::mysql' => 0,
  'File::Slurp' => 0,
	'Dancer::Session::DBI' => 0,
	'DBD::mysql' => 0,
	'List::MoreUtils' => 0,
	'Moo' => 0,
	'Moose' => 0,
	'Try::Tiny' => 0,
	'URI::Escape' => 0,
	'POSIX' => 0,
	'DateTime' => 0,
	'DateTime::Format::Strptime' => 0,
	'Scalar::Util' => 0,
	'Data::Util' => 0,
	'Dancer::Plugin::Auth::RBAC' => 0,
  'Dancer::Plugin::Email' => 0,
	'Hash::Merge::Simple' => 0,
	'Digest::MD5' => 0,
	'Cache::FastMmap' => 0,
	'ClamAV::Client' => 0,
	'Array::Diff' => 0,		
	'Image::ExifTool' => 0,
	'enum' => 0,
	'Time::Seconds' => 0,
	'Template::Plugin::POSIX' => 0,
  'Template::Plugin::JSON' => 0,
  'Time::Interval' => 0,
  'File::MimeInfo' => 0,
  'IO::CaptureOutput' => 0,
  'CAM::PDF' => 0,
  'PDF::API2' => 0,
  'Hash::Merge' => 0,
  'File::Pid' => 0,
  'Catmandu::FedoraCommons' => 0,
  'Template::Plugin::File' => 0,
  'Catmandu::MediaMosa' => 0,
  'XML::Simple' => 0
};
my $recommends = {
	'Starman' => 0
};
my $build = Module::Build->new(
	module_name => 'Imaging',
	dist_version => '0.01',
	dist_author => [qw(
		nicolas.franck@ugent.be
	)],
	dist_abstract => 'LibreCat compliant web application for UGENT Library Scanning Workflow',
	requires => $requires,
	recommends => $recommends,
	create_license => 1
);
$build->create_build_script();
