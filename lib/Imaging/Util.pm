package Imaging::Util;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Exporter qw(import);

our @EXPORT_OK = qw(data_at);

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

__PACKAGE__;
