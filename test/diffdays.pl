#!/usr/bin/env perl
use Catmandu::Sane;
use Time::HiRes;
use POSIX;

sub seconds_day {
    state $seconds_day = 3600*24;
}

sub diff_days {
    my($date1,$date2)=@_;
    my $diff = ($date2 - $date1) / seconds_day();
    if($diff > 0){
        $diff = POSIX::floor($diff);
    }else{
        $diff = POSIX::ceil($diff);
    }
    return $diff;
}

my $a = int(shift || time);
my $b = int(shift || time);
say diff_days(time,time + (seconds_day() * 2));
