package Imaging::Util;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename;
use File::MimeInfo;
use File::Find;
use Exporter qw(import);

our @EXPORT_OK = qw(data_at file_info mtime mtime_latest_file);
our %EXPORT_TAGS = (
    files => [qw(file_info mtime_latest_file mtime)],
    data => [qw(data_at)]
);

sub _data_at {
    my($val,@keys) = @_;
    my($key) = @keys;
    if(scalar(@keys) > 1){
        if(is_natural($key)){
            if(is_array_ref($val) && $key <= scalar(@$val)){
                shift @keys;
                return _data_at($val->[$key],@keys);
            }else{
                return undef;
            }
        }
        elsif(is_hash_ref($val)){
            shift @keys;
            return _data_at($val->{$key},@keys);
        }else{
            return undef;
        }

    }elsif(scalar(@keys) > 0){
        if(is_natural($key) && is_array_ref($val)){
            return ($key <= scalar(@$val) ) ? $val->[$key]:undef;
        }elsif(is_hash_ref($val)){
            return $val->{$key};
        }else{
            return undef;
        }

    }else{
        return $val;
    }

}
sub data_at {
    my($val,$test) = @_;
    _data_at($val,defined $test ? split(/\./o,$test) : qw());
}
sub file_info {
    my $path = shift;
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=lstat($path);
    if($dev){
        return {
            name => basename($path),
            path => $path,
            atime => $atime,
            mtime => $mtime,
            ctime => $ctime,
            size => $size,
            content_type => mimetype($path),
            mode => $mode
        };
    }else{
        return {
            name => basename($path),
            path => $path,
            error => $!
        }
    }
}
sub mtime {
    (lstat(shift))[9];
}
sub mtime_latest_file {
    my $dir = shift;
    my $max_mtime = 0;
    my $latest_file;
    find({
        wanted => sub{
            my $mtime = mtime($_);
            if($mtime > $max_mtime){
                $max_mtime = $mtime;
                $latest_file = $_;
            }
        },
        no_chdir => 1
    },$dir);
    return $max_mtime;
}

__PACKAGE__;
