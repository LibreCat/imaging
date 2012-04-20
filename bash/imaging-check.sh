#!/bin/bash
dir=`dirname $0`
bin="$dir/../perl/cron-check.pl"
echo "imaging check started at" `date` 
echo ""

$bin
