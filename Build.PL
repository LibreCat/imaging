use warnings;
use strict;
use Module::Build;

my $requires = {
	perl => '>=5.10.0',
	Dancer => '>=1.3091',
	Plack => '>=0.9985',

	'Dancer::Session::PSGI' => 0,
	'Dancer::Session::Cookie' => 0,
	'DBD::SQLite' => 0,
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
	'Dancer::Plugin::Auth::RBAC' => '>=1.110720',
	'Data::Pageset' => 0,
	'Hash::Merge::Simple' => 0,
	'Digest::MD5' => 0,
	'Cache::FastMmap' => 0,
	'ClamAV::Client' => 0,
	'Array::Diff' => 0,		
	'Image::ExifTool' => 0,
	'enum' => 0,
	'Time::Seconds' => 0
};
my $recommends = {
	'Starman' => 0,
	'DBD::mysql' => 0
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
