#/usr/bin/env perl
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
sub locations {
	state $locations = store()->bag("locations");
}
sub index_locations {
	state $index_locations = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core0"
    )->bag;
}
sub index_log {
	state $index_log = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core1"
    )->bag;
}
locations->delete_all();
index_locations->delete_all();
index_locations->commit();
index_locations->store->solr->optimize;
index_log->delete_all();
index_log->commit;
index_log->store->solr->optimize();
