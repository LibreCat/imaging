#!/usr/bin/env perl
use Catmandu::Sane;
use Data::Util qw(:check);

sub _test_deep_hash {
    my($hash,@keys) = @_;
    say join(',',@keys);
    my $key = pop @keys;
    say join(',',@keys);
    if(!is_hash_ref($hash->{$key})){
        return 0;
    }else{
        return _test_deep_hash(
            $hash->{$key},@keys
        );
    }
}
sub test_deep_hash {
    my($hash,$test) = @_;
    say $test;
    say split('.',$test);
    _test_deep_hash($hash,split('.',$test));
}

say test_deep_hash({
    a => 1
},"a.b");
