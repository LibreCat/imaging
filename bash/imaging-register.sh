#!/bin/bash
dir=`dirname $0`
bin=`realpath "$dir/../perl/cron-register.pl"`
echo "imaging register started at" `date` 
echo ""

$bin
