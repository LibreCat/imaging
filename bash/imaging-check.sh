#!/bin/bash
dir=`dirname $0`
bin=`realpath "$dir/../perl/cron-check.pl"`
echo "imaging check started at" `date` 
echo ""

$bin
