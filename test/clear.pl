#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;

#variabelen
sub store_opts {
	state $opts = {
		data_source => "dbi:mysql:database=imaging",
        username => "imaging",
        password => "imaging"
	};
}
sub store {
	state $store = Catmandu::Store::DBI->new(%{ store_opts() });
}
sub scans {
	state $scans = store()->bag("scans");
}
sub index_scans {
	state $index_scans = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core0"
    )->bag;
}
sub index_log {
	state $index_log = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core1"
    )->bag;
}
scans->delete_all();
index_scans->delete_all();
index_scans->commit();
index_scans->store->solr->optimize;
index_log->delete_all();
index_log->commit;
index_log->store->solr->optimize();
