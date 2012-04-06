package Imaging::Test::Dir;
use Catmandu::Sane;
use Data::Util qw(:check :validate);
use Moo::Role;
use File::Basename;
use File::Find;
use File::Spec;
use Cwd qw(cwd getcwd fastcwd fastgetcwd chdir abs_path fast_abs_path realpath fast_realpath);
use Try::Tiny;

sub import {
	Catmandu::Sane->import;
	Data::Util->import(qw(:check :validate));
	File::Basename->import;	
	File::Find->import;
	Cwd->import(qw(cwd getcwd fastcwd fastgetcwd chdir abs_path fast_abs_path realpath fast_realpath));
	Try::Tiny->import;
}
sub _load_file_info {
	my $self = shift;
	my @file_info = ();
	find({
		wanted => sub{
			return if abs_path($_) eq abs_path($self->dir);
			push @file_info,{
				dirname => abs_path($File::Find::dir),
				basename => basename($_),
				path => abs_path($File::Find::name)
			};
		},
		no_chdir => 1
	},$self->dir);
	$self->file_info(\@file_info);
}
sub is_valid_basename {
	my($self,$basename)=@_;
	foreach my $pattern(@{ $self->valid_patterns }){
		return 1 if $basename =~ $pattern;
	}
	return 0;
}

has dir => (
	is => 'rw',
	isa => sub{ (is_string($_[0]) && -d $_[0]) || die("directory not given or does not exist"); },
	required => 1,
	trigger => sub {
		$_[0]->_load_file_info();
	}
);
has file_info => (
	is => 'rw',
	isa => sub{ array_ref($_[0]); },
	lazy => 1,
	default => sub{ []; }
);
has valid_patterns => (
	is => 'rw',
	isa => sub{ 
		my $array = shift;
		array_ref($array);
		foreach(@$array){
			if(!is_rx($_)){
				$_ = qr/$_/;
			}
		}
		rx($_) foreach(@$array);
	},
	default => sub {
		[qr/.*/];
	}
);

requires 'test';

1;
