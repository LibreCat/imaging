#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);

use Catmandu::Sane;
use Catmandu::Store::DBI;
use Catmandu::Store::Solr;
use Catmandu::Util qw(require_package :is);
use List::MoreUtils qw(first_index);
use File::Basename qw();
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
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
use File::MimeInfo;

BEGIN {
    my $appdir = Cwd::realpath("..");
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);
}

#variabelen
sub xml_simple {
    state $xml_simple = XML::Simple->new();
}
sub file_info {
    my $path = shift;
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($path);
    if($dev){
        return {
            name => File::Basename::basename($path),
            path => $path,
            atime => $atime,
            mtime => $mtime,
            ctime => $ctime,
            size => $size,
            content_type => mimetype($path),
            mode => $mode
        };
    }else{
        return {
            name => File::Basename::basename($path),
            path => $path,
            error => $!
        }
    }
}
sub core_opts {
    state $opts = do {
        my $config = Catmandu->config;
        {
            data_source => $config->{store}->{core}->{options}->{data_source},
            username => $config->{store}->{core}->{options}->{username},
            password => $config->{store}->{core}->{options}->{password}
        };
    };
}
sub core {
    state $core = store("core");
}
sub projects {
    state $projects = core()->bag("projects");
}
sub scans {
    state $scans = core()->bag("scans");
}
sub meercat {
    state $meercat = WebService::Solr->new(
        config->{'index'}->{meercat}->{url},
        {default_params => {wt => 'json'}}
    );
}
sub index_scans {
    state $index_scans = store("index")->bag;
}
sub index_log {
    state $index_log = store("index_log")->bag;
}
sub mount_conf {
    config->{mounts}->{directories} ||= {};
}
sub users {
    state $users = do {
        my $opts = core_opts();
        DBI->connect($opts->{data_source}, $opts->{username}, $opts->{password}, {
            AutoCommit => 1,
            RaiseError => 1,
            mysql_auto_reconnect => 1
        });
    };
}
sub users_each {
    state $users_each = users->prepare("select * from users where has_dir = 1'");
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
    my $scan = shift;
    my $doc;
    my $index_log = index_log();
    my $users_get = users_get();
    $users_get->execute( $scan->{user_id} ) or die($users_get->errstr);
    my $user = $users_get->fetchrow_hashref();

    foreach my $history(@{ $scan->{status_history} || [] }){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{scan_id} = $scan->{_id};
        $doc->{owner} = $user->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
    $doc;
}
sub marcxml_flatten {
    my $xml = shift;
    my $ref = xml_simple->XMLin($xml,ForceArray => 1);
    my @text = ();
    foreach my $marc_datafield(@{ $ref->{'marc:datafield'} }){
        foreach my $marc_subfield(@{$marc_datafield->{'marc:subfield'}}){
            next if !is_string($marc_subfield->{content});
            push @text,$marc_subfield->{content};
        }
    }
    foreach my $control_field(@{ $ref->{'marc:controlfield'} }){
        next if !is_string($control_field->{content});
        push @text,$control_field->{content};
    }
    return \@text;
}
sub scan2index {
    my $scan = shift;       

    my $doc = clone($scan);
    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} }); 
    
    $doc->{text} = [];
    push @{ $doc->{text} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});

    my @deletes = qw(metadata comments busy busy_reason);
    delete $doc->{$_} foreach(@deletes);
    $doc->{metadata_id} = \@metadata_ids;

    $doc->{files} = [ map { $_->{path} } @{ $scan->{files} || [] } ];

    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_name}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    my $project;
    if($scan->{project_id} && ($project = projects()->get($scan->{project_id}))){
        foreach my $key(keys %$project){
            next if $key eq "list";
            my $subkey = "project_$key";
            $subkey =~ s/_{2,}/_/go;
            $doc->{$subkey} = $project->{$key};
        }
    }

    if($scan->{user_id}){
        my $users_get = users_get();
        $users_get->execute( $scan->{user_id} ) or die($users_get->errstr);
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

    index_scans()->add($doc);
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
say "\nupdating list scans for projects:\n";
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

#stap 2: ken scans toe aan projects
say "\nassigning scans to projects\n";
projects()->each(sub{
    my $project = shift;
    if(!is_array_ref($project->{list})){
        say "\tproject $project->{_id}: no list available";
        return;
    }
    foreach my $item(@{ $project->{list} }){
        
        my($scan_name);
        my @ids = ();

        # name: liefst het plaatsnummer, en indien niet mogelijk het rug01-nummer
        if($item->{location}){
            $scan_name = $item->{location};
        }else{
            $scan_name = $item->{source}.":".$item->{fSYS};
        }

        # id: plaatsnummer of rug01 mogelijk (verschil met name: letters verwisseld, en bijkomende nummering mogelijk bij plaatsnummers)
        if($item->{location}){
            my $scan_id = $item->{location};
            $scan_id =~ s/[\.\/]/-/go;
            if(defined($item->{number})){
                $scan_id .= "-".$item->{number};        
            }
            push @ids,$scan_id;         

        }
        push @ids,uc($item->{source})."-".$item->{fSYS};

        foreach my $id(@ids){

            my $scan = scans()->get($id);

            #directory nog niet aanwezig
            if(!$scan){
                say "\tproject ".$project->{_id}.":scan $id not found";
                next;
            }

            #scan toekennen aan project
            if(!$scan->{project_id}){
                $scan->{name} = $scan_name;
                $scan->{project_id} = $project->{_id};
            }

            say "\tproject ".$project->{_id}.":scan $id assigned to project";
            scans()->add($scan);

            last;
        }
    }
});

#stap 3: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
say "\nretrieving metadata for good scans:\n";
my @ids_ok_for_metadata = ();
scans()->each(sub{
    my $scan = shift;
    my $status = $scan->{status};
    my $metadata = $scan->{metadata};
    if( $status ne "incoming" && $status ne "incoming_error" && !(is_array_ref($metadata) && scalar(@$metadata) > 0 )){
        push @ids_ok_for_metadata,$scan->{_id};
    }
});
foreach my $id(@ids_ok_for_metadata){
    my $scan = scans()->get($id);
    my $query = $scan->{_id};
    if($query !~ /^RUG01-/o){
        $query =~ s/^RUG01-/rug01:/o;
    }else{
        $query = "location:$query";
    }
    my $res = meercat()->search($query,{rows=>1000});
    $scan->{metadata} = [];
    if($res->content->{response}->{numFound} > 0){

        my $docs = $res->content->{response}->{docs};
        foreach my $doc(@$docs){
            push @{ $scan->{metadata} },{
                fSYS => $doc->{fSYS},#000000001
                source => $doc->{source},#rug01
                fXML => $doc->{fXML},
                baginfo => marcxml2baginfo($doc->{fXML})
            };
        }

    }
    my $num = scalar(@{$scan->{metadata}});
    say "\tscan ".$scan->{_id}." has $num metadata-records";
    scans()->add($scan);
}

#stap 4: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
scans()->each(sub{
    my $scan = shift;
    push @incoming_ok,$scan->{_id} if $scan->{status} eq "incoming_ok";
});
say "\nregistering incoming_ok\n";
foreach my $id (@incoming_ok){
    my $scan = scans()->get($id);
    say "\tscan $id:";

    #status 'registering'
    $scan->{status} = "registering";
    push @{ $scan->{status_history} },{
        user_name =>"-",
        status => "registering",
        datetime => Time::HiRes::time,
        comments => ""
    };

    #=> registratie kan lang duren (move!), waardoor map uit /ready verdwijnt, maar ondertussen ook in /scans is terug te vinden
    #=> daarom opnemen in databank én indexeren
    scans->add($scan);
    scan2index($scan);
    index_scans->commit();

    status2index($scan);
    index_log->commit();

    #pas manifest -> maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)
        
    #verwijder oude manifest vóóraf, want anders duikt oude manifest op in ... manifest.txt
    unlink($scan->{path}."/manifest.txt") if -f $scan->{path}."/manifest.txt";
    my $index = first_index { $_ eq $scan->{path}."/manifest.txt" } map { $_->{path} } @{ $scan->{files} };
    splice(@{ $scan->{files} },$index,1) if $index >= 0;

    say "\tcreating new manifest.txt";

    #maak nieuwe manifest
    local(*MANIFEST);
    open MANIFEST,">".$scan->{path}."/manifest.txt" or die($!);
    foreach my $file(@{ $scan->{files} }){
        local(*FILE);
        open FILE,$file->{path} or die($!);
        my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
        say MANIFEST "$md5sum_file ".File::Basename::basename($file->{path});
        close FILE;
    }
    close MANIFEST;

    #voeg manifest toe aan de lijst
    push @{ $scan->{files} },file_info($scan->{path}."/manifest.txt");
    

    #verplaats  
    my $oldpath = $scan->{path};
    my $mount_conf = mount_conf();
    my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".File::Basename::basename($oldpath);
    say "\tmoving from $oldpath to $newpath";
    move($oldpath,$newpath);
    $scan->{path} = $newpath;
    foreach my $file(@{ $scan->{files} }){
        $file->{path} =~ s/^$oldpath/$newpath/;
    }

    #update file info
    foreach my $file(@{ $scan->{files} }){
        my $new_stats = file_info($file->{path});
        $file->{$_} = $new_stats->{$_} foreach(keys %$new_stats);
    }
    
    #status 'registered'
    $scan->{status} = "registered";
    push @{ $scan->{status_history} },{
        user_name =>"-",
        status => "registered",
        datetime => Time::HiRes::time,
        comments => ""
    };
    
    scans->add($scan);
    scan2index($scan);
    index_scans->commit();

    status2index($scan);
    index_log->commit();
}

#stap 5: indexeer
say "\nindexing merge scans-projects-users\n";
scans->each(sub{
    my $scan = shift;
    my $doc = scan2index($scan);
    say "\tscan $scan->{_id} added to index";
});
index_scans->commit();
index_scans->store->solr->optimize();

#stap 6: indexeer logs
say "\nlogging:\n";
scans()->each(sub{
    my $scan = shift;
    my $doc = status2index($scan);
    say "\tscan $scan->{_id} added to log (_id:$doc->{_id})" if $doc;
});
index_log->commit();
index_log->store->solr->optimize();
