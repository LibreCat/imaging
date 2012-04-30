#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(load_package :is);
use List::MoreUtils qw(first_index);
use File::Basename;
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use open qw(:std :utf8);
use YAML;
use Try::Tiny;
use DBI;
use Clone qw(clone);
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use WebService::Solr;
use Digest::MD5 qw(md5_hex);
use Catmandu::Importer::MARC;
use Catmandu::Fix;
use Time::HiRes;
use XML::Simple;

#variabelen
sub xml_simple {
    state $xml_simple = XML::Simple->new();
}
sub file_info {
    my $path = shift;
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($path);
    if($dev){
        return {
            name => basename($path),
            path => $path,
            atime => $atime,
            mtime => $mtime,
            ctime => $ctime,
            size => $size,
            mode => $mode
        };
    }else{
        return {
            name => basename($path),
            path => $path,
            error => $!
        }
    }
}
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
sub projects {
    state $projects = store()->bag("projects");
}
sub locations {
    state $locations = store()->bag("locations");
}
sub profiles {
    state $profiles = store()->bag("profiles");
}
sub meercat {
    state $meercat = WebService::Solr->new(
        "http://localhost:4000/solr",{default_params => {wt => 'json'}}
    );
}
sub index_locations {
    state $index_locations = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core0"
    )->bag("locations");
}
sub index_log {
    state $index_log = Catmandu::Store::Solr->new(
        url => "http://localhost:8983/solr/core1"
    )->bag("log_locations");
}
sub mount_conf {
    state $mount_conf = do {
        my $dir = dirname(__FILE__);
        my $conf = YAML::LoadFile("$dir/../environments/development.yml");
        my $mount_conf = $conf->{mounts}->{directories};
    };
}
sub users {
    state $users = do {
        my $opts = store_opts();
        DBI->connect($opts->{data_source}, $opts->{username}, $opts->{password}, {
            AutoCommit => 1,
            RaiseError => 1,
            mysql_auto_reconnect => 1
        });
    };
}
sub users_each {
    state $users_each = users->prepare("select * from users where roles like '%scanner'");
}
sub users_get {
    state $users_get = users->prepare("select * from users where id = ?");
}

sub formatted_date {
    my $time = shift || Time::HiRes::time;
    DateTime::Format::Strptime::strftime(
        '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}
sub status2index {
    my $location = shift;
    my $doc;
    my $index_log = index_log();
    my $users_get = users_get();
    $users_get->execute( $location->{user_id} ) or die($users_get->errstr);
    my $user = $users_get->fetchrow_hashref();

    foreach my $history(@{ $location->{status_history} || [] }){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{location_id} = $location->{_id};
        $doc->{owner} = $user->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
    $doc;
}
sub location2index {
    my $location = shift;       

    my $doc = clone($location);
    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $location->{metadata} }); 
    my @deletes = qw(metadata comments busy busy_reason);
    delete $doc->{$_} foreach(@deletes);
    $doc->{metadata_id} = \@metadata_ids;

    $doc->{files} = [ map { $_->{path} } @{ $location->{files} || [] } ];

    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_name}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    my $project;
    if($location->{project_id} && ($project = projects()->get($location->{project_id}))){
        foreach my $key(keys %$project){
            next if $key eq "list";
            my $subkey = "project_$key";
            $subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }

    if($location->{user_id}){
        my $users_get = users_get();
        $users_get->execute( $location->{user_id} ) or die($users_get->errstr);
        my $user = $users_get->fetchrow_hashref();
        if($user){
            $doc->{user_name} = $user->{name};
            $doc->{user_login} = $user->{login};
            $doc->{user_roles} = [split(',',$user->{roles})];
        }
    }

    foreach my $key(keys %$doc){
        next if $key !~ /datetime/o;
        $doc->{$key} = formatted_date($doc->{$key});
    }

    index_locations()->add($doc);
    $doc;
}

our $marc_type_map = { 
    'article'        => 'Text' ,
    'audio'          => 'Sound' ,
    'book'           => 'Text' ,
    'coin'           => 'Image' ,
    'cursus'         => 'Text' ,
    'database'       => 'Dataset' ,
    'digital'        => 'Dataset' ,
    'dissertation'   => 'Text' ,
    'ebook'          => 'Text' ,
    'ephemera'       => 'Text' ,
    'film'           => 'MovingImage' ,
    'image'          => 'Image' ,
    'manuscript'     => 'Text' ,
    'map'            => 'Image' ,
    'medal'          => 'Image' ,
    'microform'      => 'Text' ,
    'mixed'          => 'Dataset' ,
    'music'          => 'Sound' ,
    'newspaper'      => 'Text' ,
    'periodical'     => 'Text' ,
    'plan'           => 'Image' ,
    'poster'         => 'Image' ,
    'score'          => 'Text' ,
    'videorecording' => 'MovingImage' ,
    '-'              => 'Text'
};
sub marcxml2baginfo {
    my $xml = shift;

    use XML::XPath;
    use POSIX qw(strftime);

    my $xpath = XML::XPath->new(xml => $xml);
    my $rec = {};
    my @fields = qw(
        DC-Title DC-Identifier DC-Description DC-DateAccepted DC-Type DC-Creator DC-AccessRights DC-Subject
    );
    $rec->{$_} = [] foreach(@fields);

    my $id = &marc_controlfield($xpath,'001');

    push(@{$rec->{'DC-Title'}}, "RUG01-$id");

    push(@{$rec->{'DC-Identifier'}}, "rug01:$id");
    for my $val (&marc_datafield_array($xpath,'852','j')){
        push(@{$rec->{'DC-Identifier'}}, $val) if $val =~ /\S/o;
    }
    my $f035 = &marc_datafield($xpath,'035','a');
    push(@{$rec->{'DC-Identifier'}}, $f035) if $f035;

    my $description = &marc_datafield($xpath,'245');
    push(@{$rec->{'DC-Description'}}, $description);

    #push(@{$rec->{'DC-DateAccepted'}}, strftime("%Y-%m-%d",localtime));

    my $type = &marc_datafield($xpath,'920','a');
    push(@{$rec->{'DC-Type'}}, $marc_type_map->{$type} || $marc_type_map->{'-'});

    my $creator = &marc_datafield($xpath,'100','a');
    push(@{$rec->{'DC-Creator'}}, $creator) if $creator;

    for my $val (&marc_datafield_array($xpath,'700','a')) {
        push(@{$rec->{'DC-Creator'}}, $val) if $val =~ /\S/;
    }

    my $rights = &marc_datafield($xpath,'856','z');
    if ($rights =~ /no access/io) {
        push(@{$rec->{'DC-AccessRights'}}, 'closed');
    }
    elsif ($rights =~ /ugent/io) {
        push(@{$rec->{'DC-AccessRights'}}, 'ugent');
    }
    else {
        push(@{$rec->{'DC-AccessRights'}}, 'open');
    }

    for my $subject (&marc_datafield_array($xpath,'922','a')) {
        push(@{$rec->{'DC-Subject'}}, $subject) if $subject =~ /\S/;
    }

    return $rec;
}
sub str_clean {
    my $str = shift;
    $str =~ s/\n//gom;
    $str =~ s/^\s+//go;
    $str =~ s/\s+$//go;
    $str =~ s/\s\s+/ /go;
    $str;
}
sub marc_controlfield {
    my $xpath = shift;
    my $field = shift;
    
    my $search = '/marc:record';
    $search .= "/marc:controlfield[\@tag='$field']" if $field; 
    return &str_clean($xpath->findvalue($search)->to_literal->value);
}
sub marc_datafield {
    my $xpath = shift;
    my $field = shift;
    my $subfield = shift;

    my $search = '/marc:record';
    $search .= "/marc:datafield[\@tag='$field']" if $field; 
    $search .= "/marc:subfield[\@code='$subfield']" if $subfield;
    return &str_clean($xpath->findvalue($search)->to_literal->value);
}
sub marc_datafield_array {
    my $xpath = shift;
    my $field = shift;
    my $subfield = shift;

    my $search = '/marc:record';
    $search .= "/marc:datafield[\@tag='$field']" if $field; 
    $search .= "/marc:subfield[\@code='$subfield']" if $subfield;

    my @vals = (); 
    for my $node ($xpath->find($search)->get_nodelist) {
      push @vals , $node->string_value;
    }

    return @vals;
}

#stap 1: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "\nupdating list locations for projects:\n";
my @project_ids = ();
projects()->each(sub{ 
    push @project_ids,$_[0]->{_id}; 
});

foreach my $project_id(@project_ids){

    my $project = projects()->get($project_id);
    my $total = 0;

    my $query = $project->{query};
    next if !$query;

    my @list = ();

    my $meercat = meercat();
    my $res = $meercat->search($query,{rows=>0});
    $total = $res->content->{response}->{numFound};

    my($offset,$limit) = (0,1000);
    while($offset <= $total){
        $res = $meercat->search($query,{start => $offset,rows => $limit});
        my $hits = $res->content->{response}->{docs};

        foreach my $hit(@$hits){
            my $ref = xml_simple->XMLin($hit->{fXML},ForceArray => 1);

            #zoek items in Z30 3, en nummering in Z30 h
            my @items = ();

            foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
                if($marc_datafield->{tag} eq "Z30"){
                    my $item = {
                        source => $hit->{source},
                        fSYS => $hit->{fSYS}
                    };
                    foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
                        if($marc_subfield->{code} eq "3"){
                            $item->{"location"} = $marc_subfield->{content};
                        }
                        if($marc_subfield->{code} eq "h" && $marc_subfield->{content} =~ /^V\.\s+(\d+)$/o){
                            $item->{"number"} = $1;
                        }
                    }
                    say join(',',values %$item);
                    push @items,$item;
                }
            }
            push @list,@items;
        }
        $offset += $limit;
    }

    $project->{list} = \@list;
    $project->{datetime_last_modified} = Time::HiRes::time;
    $project->{locked} = 1;

    projects()->add($project);
};

#stap 2: ken locations toe aan projects
say "\nassigning locations to projects\n";
projects()->each(sub{
    my $project = shift;
    if(!is_array_ref($project->{list})){
        say "\tproject $project->{_id}: no list available";
        return;
    }
    foreach my $item(@{ $project->{list} }){
        
        my($location_name);
        my @ids = ();

        # name: liefst het plaatsnummer, en indien niet mogelijk het rug01-nummer
        if($item->{location}){
            $location_name = $item->{location};
        }else{
            $location_name = $item->{source}.":".$item->{fSYS};
        }

        # id: plaatsnummer of rug01 mogelijk (verschil met name: letters verwisseld, en bijkomende nummering mogelijk bij plaatsnummers)
        if($item->{location}){
            my $location_id = $item->{location};
            $location_id =~ s/[\.\/]/-/go;
            if(defined($item->{number})){
                $location_id .= "-".$item->{number};        
            }
            push @ids,$location_id;         

        }
        push @ids,uc($item->{source})."-".$item->{fSYS};

        foreach my $id(@ids){

            my $location = locations()->get($id);

            #directory nog niet aanwezig
            if(!$location){
                say "\tproject ".$project->{_id}.":location $id not found";
                next;
            }

            #location toekennen aan project
            if(!$location->{project_id}){
                $location->{name} = $location_name;
                $location->{project_id} = $project->{_id};
            }

            say "\tproject ".$project->{_id}.":location $id assigned to project";
            locations()->add($location);

            last;
        }
    }
});

#stap 3: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
say "\nretrieving metadata for good locations:\n";
my @ids_ok_for_metadata = ();
locations()->each(sub{
    my $location = shift;
    my $status = $location->{status};
    my $metadata = $location->{metadata};
    if( $status ne "incoming" && $status ne "incoming_error" && !(is_array_ref($metadata) && scalar(@$metadata) > 0 )){
        push @ids_ok_for_metadata,$location->{_id};
    }
});
foreach my $id(@ids_ok_for_metadata){
    my $location = locations()->get($id);
    my $query = $location->{_id};
    if($query !~ /^RUG01-/o){
        $query =~ s/^RUG01-/rug01:/o;
    }else{
        $query = "location:$query";
    }
    my $res = meercat()->search($query,{rows=>1000});
    $location->{metadata} = [];
    if($res->content->{response}->{numFound} > 0){

        my $docs = $res->content->{response}->{docs};
        foreach my $doc(@$docs){
            push @{ $location->{metadata} },{
                fSYS => $doc->{fSYS},#000000001
                source => $doc->{source},#rug01
                fXML => $doc->{fXML},
                baginfo => marcxml2baginfo($doc->{fXML})
            };
        }

    }
    my $num = scalar(@{$location->{metadata}});
    say "\tlocation ".$location->{_id}." has $num metadata-records";
    locations()->add($location);
}

#stap 4: registreer locations die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
locations()->each(sub{
    my $location = shift;
    push @incoming_ok,$location->{_id} if $location->{status} eq "incoming_ok";
});
say "\nregistering incoming_ok\n";
foreach my $id (@incoming_ok){
    my $location = locations()->get($id);
    say "\tlocation $id:";

    #status 'registering'
    $location->{status} = "registering";
    push @{ $location->{status_history} },{
        user_name =>"-",
        status => "registering",
        datetime => Time::HiRes::time,
        comments => ""
    };

    #=> registratie kan lang duren (move!), waardoor map uit /ready verdwijnt, maar ondertussen ook in /locations is terug te vinden
    #=> daarom opnemen in databank én indexeren
    locations->add($location);
    location2index($location);
    index_locations->commit();

    status2index($location);
    index_log->commit();

    #pas manifest -> maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)
        
    #verwijder oude manifest vóóraf, want anders duikt oude manifest op in ... manifest.txt
    unlink($location->{path}."/manifest.txt") if -f $location->{path}."/manifest.txt";
    my $index = first_index { $_ eq $location->{path}."/manifest.txt" } map { $_->{path} } @{ $location->{files} };
    splice(@{ $location->{files} },$index,1) if $index >= 0;

    say "\tcreating new manifest.txt";

    #maak nieuwe manifest
    local(*MANIFEST);
    open MANIFEST,">".$location->{path}."/manifest.txt" or die($!);
    foreach my $file(@{ $location->{files} }){
        local(*FILE);
        open FILE,$file->{path} or die($!);
        my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
        say MANIFEST "$md5sum_file ".basename($file->{path});
        close FILE;
    }
    close MANIFEST;

    #voeg manifest toe aan de lijst
    push @{ $location->{files} },file_info($location->{path}."/manifest.txt");
    

    #verplaats  
    my $oldpath = $location->{path};
    my $mount_conf = mount_conf();
    my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".basename($oldpath);
    say "\tmoving from $oldpath to $newpath";
    move($oldpath,$newpath);
    $location->{path} = $newpath;
    foreach my $file(@{ $location->{files} }){
        $file->{path} =~ s/^$oldpath/$newpath/;
    }

    #update file info
    foreach my $file(@{ $location->{files} }){
        my $new_stats = file_info($file->{path});
        $file->{$_} = $new_stats->{$_} foreach(keys %$new_stats);
    }
    
    #status 'registered'
    $location->{status} = "registered";
    push @{ $location->{status_history} },{
        user_name =>"-",
        status => "registered",
        datetime => Time::HiRes::time,
        comments => ""
    };
    
    locations->add($location);
    location2index($location);
    index_locations->commit();

    status2index($location);
    index_log->commit();
}

#stap 5: indexeer
say "\nindexing merge locations-projects-users\n";
locations->each(sub{
    my $location = shift;
    my $doc = location2index($location);
    say "\tlocation $location->{_id} added to index";
});
index_locations->commit();
index_locations->store->solr->optimize();

#stap 6: indexeer logs
say "\nlogging:\n";
locations()->each(sub{
    my $location = shift;
    my $doc = status2index($location);
    say "\tlocation $location->{_id} added to log (_id:$doc->{_id})" if $doc;
});
index_log->commit();
index_log->store->solr->optimize();
