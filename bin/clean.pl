#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu qw(:load store);
use JSON qw(encode_json);

Catmandu->load;
print encode_json(Catmandu->config);

#store("core")->bag("scans")->each(sub{
#    print encode_json(shift);
#});
