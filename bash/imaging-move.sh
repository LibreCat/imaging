#!/bin/bash
dir=`dirname $0`
bin="$dir/../perl/cron-move.pl"
echo "imaging move started at" `date` 
echo ""

$bin
