package Imaging::Test::Dir::checkBag;
use Catmandu::Sane;
use Moo;
use Data::Util qw(:validate :check);
use Try::Tiny;
use Archive::BagIt;
use File::Basename;

has _bagit => (
    is => 'ro',
    lazy => 1,
    isa => sub{ instance($_[0],'Archive::BagIt'); },
    default => sub {
        Archive::BagIt->new;
    }
);
has validate => (
    is => 'ro',
    lazy => 1,
    default => sub{ 0; }
);
sub is_fatal {
    1;
};

sub test {
    my $self = shift;
    my $topdir = $self->dir_info->dir();
    my(@errors) = ();

    my $read_successfull = $self->_bagit->read($topdir);
    if(!$read_successfull){
        my $bagit_errors = $self->_bagit->_error;
        if(is_array_ref($bagit_errors) && scalar(@$bagit_errors) > 0){
            foreach(@$bagit_errors){
                if(/bagit\.txt/o){
                    push @errors,basename($topdir).":bagit.txt bestaat niet";
                }elsif(/(package-info\.txt|bag-info\.txt)/o){
                    push @errors,basename($topdir).":package-info.txt of bag-info.txt bestaat niet";
                }elsif(/manifest-md5\.txt/o){
                    push @errors,basename($topdir).":manifest-md5.txt bestaat niet";
                }
            }
        }else{
            push @errors,basename($topdir).": bag validatie faalde om niet gekende redenen";
        }
    }else{
        if($self->validate){
            if(!$self->_bagit->valid){
                push @errors,@{ $self->_bagit->_error || [] };
            }
        }elsif(!$self->_bagit->complete){
            push @errors,@{ $self->_bagit->_error || [] };
        }
    }

    scalar(@errors) == 0,\@errors;
}   

with qw(Imaging::Test::Dir);

1;
