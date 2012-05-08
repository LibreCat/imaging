#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is);
use Cwd qw(abs_path);
use File::Spec;
use File::Basename;
use YAML;

my $profile_id = shift || die("usage:$0 <profile>\n");

my $config_file = File::Spec->catdir( dirname(dirname( abs_path(__FILE__) )),"environments")."/development.yml";
my $config = YAML::LoadFile($config_file);
my $profile = $config->{profiles}->{$profile_id} || die("profile $profile_id not found\n");

#doe check
sub get_package {
    my($class,$args)=@_;
    state $stash->{$class} ||= require_package($class)->new(%$args);
}

foreach my $path(@ARGV){

    say "checking $path";
    my @files = ();

    #acceptatie valt niet af te leiden uit het bestaan van foutboodschappen, want niet alle testen zijn 'fatal'
    my $num_fatal = 0;

    foreach my $test(@{ $profile->{packages} }){
        say $test->{class};
        my $ref = get_package($test->{class},$test->{args});
        $ref->dir($path);        
        my($success,$errors) = $ref->test();

        if(!$success){
            say "\t$_" foreach(@$errors);
        }

        if(!$success){
            if($test->{on_error} eq "stop"){
                $num_fatal = 1;
                last;
            }elsif($ref->is_fatal){
                $num_fatal++;
            }
        }
    }

}
