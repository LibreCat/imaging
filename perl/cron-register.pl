#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);
use List::MoreUtils qw(first_index);
use File::Basename qw();
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Digest::MD5 qw(md5_hex);
use Time::HiRes;
use all qw(Imaging::Dir::Query::*);
use English '-no_match_vars';
use Archive::BagIt;

my $pidfile;
BEGIN {
   
    #load configuration
    my $appdir = Cwd::realpath(
        dirname(dirname(
            Cwd::realpath( __FILE__)
        ))
    );
    Dancer::Config::setting(appdir => $appdir);
    Dancer::Config::setting(public => "$appdir/public");
    Dancer::Config::setting(confdir => $appdir);
    Dancer::Config::setting(envdir => "$appdir/environments");
    Dancer::Config::load();
    Catmandu->load($appdir);

    #voer niet uit wanneer andere instantie van imaging-register.pl draait!
    local(*PIDFILE);
    $pidfile = data_at(config,"cron.register.pidfile") ||  "/var/run/imaging-register.pid";
    if(-f $pidfile){
        local($/)=undef;
        open PIDFILE,$pidfile or die($!);
        my $pid = <PIDFILE>;
        close PIDFILE;
        if(is_natural($pid) && kill(0,$pid)){
            die("Cannot run while other registration is running (pidfile '$pidfile',pid '$pid')\n");
        }
    }
    #plaats lock
    open PIDFILE,">$pidfile" or die($!);
    print PIDFILE $$;
    close PIDFILE;

}
END {
    #verwijder lock
    unlink($pidfile) if is_string($pidfile) && -f -w $pidfile;
}

use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Imaging::Routes::Meercat;


#variabelen
sub mount_conf {
    config->{mounts}->{directories} ||= {};
}
sub directory_translator_packages {
    state $c = do {
        my $config = config;
        my $list = [];
        if(is_array_ref($config->{directory_to_query})){
            $list = $config->{directory_to_query};
        }
        $list;
    };
}
sub directory_translator {
    state $translators = {};
    my $package = shift;
    $translators->{$package} ||= $package->new;
}
sub directory_to_queries {
    my $path = shift;
    my $packages = directory_translator_packages();    
    my @queries = ();
    foreach my $p(@$packages){
        my $trans = directory_translator($p);
        if($trans->check($path)){
            @queries = $trans->queries($path);
            last;
        }
    }
    @queries;
}
sub has_manifest {
    my $path = shift;
    is_string($path) && -f "$path/__MANIFEST-MD5.txt";
}
sub has_valid_manifest {
    state $line_re = qr/^[0-9a-fA-F]+\s+.*$/;

    my $path = shift;    
    has_manifest($path) && do {
        my $valid = 1;
        try{                        
            local(*FILE);
            my $line;
            open FILE,"$path/__MANIFEST-MD5.txt" or die($!);
            while($line = <FILE>){
                $line =~ s/\r\n$/\n/;
                chomp($line);
                utf8::decode($line);
                if($line !~ $line_re){
                    $valid = 0;
                    last;
                }
            }
            close FILE;
        }catch{
            $valid = 0;
        };
        $valid;
    };
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;

#stap 1: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "updating list scans for projects";
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
            my $ref = from_xml($hit->{fXML},ForceArray => 1);

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
                    say "\t".join(',',values %$item);
                    push @items,$item;
                }
            }
            push @list,@items;
        }
        $offset += $limit;
    }

    $project->{list} = \@list;
    $project->{datetime_last_modified} = Time::HiRes::time;

    projects()->add($project);
    project2index($project);
};
{
    my($success,$error) = index_project->commit;   
    die(join('',@$error)) if !$success;
}


#stap 2: ken scans toe aan projects
say "assigning scans to projects";
my @scan_ids = ();
scans->each(sub{ 
    push @scan_ids,$_[0]->{_id} if !-f $_[0]->{path}."/__FIXME.txt"; 
});
foreach my $scan_id(@scan_ids){
    my $scan = scans->get($scan_id);
    my $result = index_project->search(query => "list:\"".$scan->{_id}."\"");
    if($result->total > 0){        
        my @project_ids = map { $_->{_id} } @{ $result->hits };
        $scan->{project_id} = \@project_ids;
        say "assigning project $_ to scan ".$scan->{_id} foreach(@project_ids);
    }else{
        $scan->{project_id} = [];
    }
    scans->add($scan);
    scan2index($scan);
}

{
    my($success,$error) = index_scan->commit;   
    die(join('',@$error)) if !$success;
}

#stap 3: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
say "retrieving metadata for good scans";
my @ids_ok_for_metadata = ();
scans()->each(sub{
    my $scan = shift;
    my $status = $scan->{status};
    my $metadata = $scan->{metadata};
    if( 
        !array_includes(["incoming","incoming_error"],$status) && 
        !(is_array_ref($metadata) && scalar(@$metadata) > 0 ) &&
        !(-f $scan->{path}."/__FIXME.txt")
    ){

        push @ids_ok_for_metadata,$scan->{_id};
    }
});
foreach my $id(@ids_ok_for_metadata){
    my $scan = scans()->get($id);
    my $path = $scan->{path};
    my @queries = directory_to_queries($path);
    
    foreach my $query(@queries){
        my $res = meercat()->search($query,{});
        $scan->{metadata} = [];
        if($res->content->{response}->{numFound} > 0){

            my $docs = $res->content->{response}->{docs};
            foreach my $doc(@$docs){
                push @{ $scan->{metadata} },{
                    fSYS => $doc->{fSYS},#000000001
                    source => $doc->{source},#rug01
                    fXML => $doc->{fXML},
                    baginfo => create_baginfo(
                        xml => $doc->{fXML},
                        size => $scan->{size},
                        num_files => scalar(@{$scan->{files}})
                    )
                };
            }
            last;

        }

    }
    my $num = scalar(@{$scan->{metadata}});
    say "\tscan ".$scan->{_id}." has $num metadata-records";
    scans()->add($scan);
    scan2index($scan);

    my($success,$error) = index_scan->commit;
    die(join('',@$error)) if !$success;
}

#stap 4: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
scans()->each(sub{
    my $scan = shift;
    if(
        $scan->{status} eq "incoming_ok" &&
        !(-f $scan->{path}."/__FIXME.txt")
    ){
        push @incoming_ok,$scan->{_id};
    }
});
say "registering incoming_ok";
foreach my $id (@incoming_ok){
    my $scan = scans()->get($id);    

    say "\tscan $id:";

    #check: tussen laatste cron-check en registratie kan de map nog aangepast zijn..
    
    my $mtime_latest_file = mtime_latest_file($scan->{path});
    if($mtime_latest_file > $scan->{datetime_last_modified}){
        say STDERR "\t\tis changed since last check, I'm sorry! Aborting..";
        next;
    }

    #check BAGS!
    if($scan->{profile_id} eq "BAG"){
        say "\t\tvalidating as bagit";
        my @errors = ();
        my $bag = Archive::BagIt->new();
        my $success = $bag->read($scan->{path});        
        if(!$success){
            push @errors,@{ $bag->_error };
        }elsif(!$bag->valid){
            push @errors,@{ $bag->_error };
        }
        if(scalar(@errors) > 0){
            say "\t\tfailed";
            $scan->{status} = "incoming_error";
            my $status_history_object = {
                user_login => "-",
                status => $scan->{status},
                datetime => Time::HiRes::time,
                comments => ""
            };
            push @{ $scan->{status_history} },$status_history_object;
            $scan->{check_log} = \@errors;

            scans->add($scan);
            scan2index($scan);
            my($success,$error) = index_scan->commit;
            die(join('',@$error)) if !$success;
            status2index($scan,-1);
            ($success,$error) = index_log->commit;
            die(join('',@$error)) if !$success;

            next;
        }else{
            say "\t\tsuccessfull";
        }
    }


    my $oldpath = $scan->{path};
    my $mount_conf = mount_conf();
    my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".File::Basename::basename($oldpath);   

    if(!has_valid_manifest($scan->{path})){

        #maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)            
        say "\tcreating __MANIFEST-MD5.txt";

        my $path_manifest = $scan->{path}."/__MANIFEST-MD5.txt";
        #maak nieuwe manifest
        local(*MANIFEST);
        open MANIFEST,">$path_manifest" or die($!);
        foreach my $file(@{ $scan->{files} }){
            next if $file->{path} eq $path_manifest;
            local(*FILE);
            open FILE,$file->{path} or die($!);
            my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
            my $filename = $file->{path};
            $filename =~ s/^$oldpath\///;
            print MANIFEST "$md5sum_file $filename\r\n";
            close FILE;
        }
        close MANIFEST;

    }
    
    #verplaats  
    say "\tmoving from $oldpath to $newpath";
    move($oldpath,$newpath);
    #chmod(0755,$newpath) is enkel van toepassing op bestanden en mappen direct onder newpath..
    `chmod -R 0755 $newpath`;    
    #toekennen aan uitvoerende gebruiker
    my $uid = getlogin || getpwuid($UID);
    my $gid = getgrgid($REAL_GROUP_ID);
    `chown -R $uid:$gid $newpath`;
    $scan->{path} = $newpath;

    #update files
    my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});
    my @files = ();
    foreach my $file(@{ $dir_info->files() }){
        push @files,file_info($file->{path});
    }
    $scan->{files} = \@files;
    $scan->{size} = $dir_info->size();
    
    #status 'registered'
    $scan->{status} = "registered";
    delete $scan->{$_} for(qw(busy));
    push @{ $scan->{status_history} },{
        user_login =>"-",
        status => "registered",
        datetime => Time::HiRes::time,
        comments => ""
    };
    $scan->{datetime_last_modified} = Time::HiRes::time;
    
    scans->add($scan);
    scan2index($scan);
    my($success,$error) = index_scan->commit;
    die(join('',@$error)) if !$success;
    status2index($scan,-1);
    ($success,$error) = index_log->commit;
    die(join('',@$error)) if !$success;
}

index_log->store->solr->optimize();
index_scan->store->solr->optimize();
index_project->store->solr->optimize();

say "$this_file ended at ".local_time;
