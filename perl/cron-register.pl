#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Imaging::Util qw(:files :data);
use Imaging::Dir::Info;
use Imaging::Bag::Info;
use Catmandu::Sane;
use Catmandu::Util qw(require_package :is :array);
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
use File::Pid;
use IO::CaptureOutput qw(capture_exec);

my $pidfile;
my $pid;
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
    $pidfile = data_at(config,"cron.register.pidfile") ||  "/var/run/imaging-register.pid";
    $pid = File::Pid->new({
        file => $pidfile
    });
    if(-f $pid->file && $pid->running){
        die("Cannot run while registration is running\n");
    }

    #plaats lock
    $pid->write;
}
END {
    #verwijder lock
    $pid->remove if $pid;
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
    if(scalar @queries == 0){
        push @queries,File::Basename::basename($path);
    }
    @queries;
}
sub update_scan {
    my $scan = shift;
    scans->add($scan);
    scan2index($scan);
    my($success,$error) = index_scan->commit;
    die(join('',@$error)) if !$success;
}
sub update_status {
    my($scan,$index) = @_;
    status2index($scan,$index);
    my($success,$error) = index_log->commit;
    die(join('',@$error)) if !$success;
}

my $this_file = File::Basename::basename(__FILE__);
say "$this_file started at ".local_time;


#stap 1: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
#
#   1ste metadata-record wordt neergeschreven in bag-info.txt: mediamosa pikt deze metadata op

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
    my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});
    my $bag_info_path = $scan->{path}."/bag-info.txt";
    my $bag_info;
    if(-f $bag_info_path){
        my $bag_info_parser = Imaging::Bag::Info->new(source => $bag_info_path);
        $bag_info = $bag_info_parser->hash;
    }
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
                        old_bag_info => $bag_info,
                        size => $dir_info->size,
                        num_files => scalar(@{ $dir_info->files() })
                    )
                };
            }
    
            last;

        }

    }
    my $num = scalar(@{$scan->{metadata}});
    say "\tscan ".$scan->{_id}." has $num metadata-records";

    update_scan($scan);
}

#stap 2: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest)
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

my $mount_conf = mount_conf();
my $dir_processed = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed};

if(!-w $dir_processed){

    #not recoverable: aborting
    say "\tcannot write to $dir_processed";    

}else{

    foreach my $id (@incoming_ok){
        my $scan = scans()->get($id);    

        say "\tscan $id:";

        if(!-w dirname($scan->{path})){

            say "\t\tcannot move $scan->{path} from parent directory";
            #not recoverable: aborting
            next;

        }         
        


        #check: tussen laatste cron-check en registratie kan de map nog aangepast zijn..
        
        my $mtime_latest_file = mtime_latest_file($scan->{path});
        if($mtime_latest_file > $scan->{datetime_last_modified}){
            say "\t\tis changed since last check, I'm sorry! Aborting..";
            #not recoverable: aborting
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

                update_scan($scan);
                update_status($scan,-1);

                #see you later!
                #not recoverable: aborting
                next;
            }else{
                say "\t\tsuccessfull";
            }
        }

        #write bag_info to bag-info.txt
        if(scalar(@{ $scan->{metadata} }) > 0){

            write_to_bag_info($scan->{path}."/bag-info.txt",$scan->{metadata}->[0]->{baginfo});

        }
        
        #ok, tijdelijk toekennen aan root zelf, opdat niemand kan tussenkomen..
        #vergeet zelfde rechten niet toe te kennen aan bovenliggende map (anders kan je verwijderen..)
        my $this_uid = getpwuid($UID);
        my $this_gid = getgrgid($EGID);

        my $uid = data_at(config,"mounts.directories.owner.processed") || $this_uid;
        my $gid = data_at(config,"mounts.directories.group.processed") || $this_gid;
        my $rights = data_at(config,"mounts.directories.rights.processed") || "0755";

        
        my($uname) = getpwnam($uid);
        if(!is_string($uname)){
            say "\t\t$uid is not a valid user name";
            #not recoverable: aborting
            next;
        }
        say "\t\tchanging ownership of '$scan->{path}' to $this_uid:$this_gid";

        {
            my $command = "chown -R $this_uid:$this_gid $scan->{path} && chmod -R 700 $scan->{path}";
            my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
            if(!$success){
                say "\t\tcannot change ownership: $stderr";
                #not recoverable: aborting
                next;
            }

        }

        my $old_path = $scan->{path};
        my $new_path = "$dir_processed/".File::Basename::basename($old_path);   


        #maak manifest aan nog vóór de move uit te voeren! (move is altijd gevaarlijk..)            
        say "\tcreating __MANIFEST-MD5.txt";   
        my $path_manifest = $scan->{path}."/__MANIFEST-MD5.txt";
        if(-f $path_manifest){
            if(!unlink($path_manifest)){
                say "\tcannot remove old __MANIFEST-MD5.txt";
                #not recoverable: aborting
                next;
            }
        }

        #maak nieuwe manifest
        if(!-w $scan->{path}){
            say "\tcannot write to directory $scan->{path}";
            #not recoverable: aborting
            next;
        }

        my $dir_info = Imaging::Dir::Info->new(dir => $scan->{path});

        local(*MANIFEST);
        open MANIFEST,">$path_manifest" or die($!);
        foreach my $file(@{ $dir_info->files() }){
            next if $file->{path} eq $path_manifest;
            local(*FILE);
            if(!(
                -f -r $file->{path}
            )){
                say "$file->{path} is not a regular file or is not readable";
                unlink($path_manifest);
                #not recoverable: aborting
                next;
            }
            open FILE,$file->{path} or die($!);
            my $md5sum_file = Digest::MD5->new->addfile(*FILE)->hexdigest;
            my $filename = $file->{path};
            $filename =~ s/^$old_path\///;
            print MANIFEST "$md5sum_file $filename\r\n";
            close FILE;
        }
        close MANIFEST;

        
        #verplaats  
        say "\tmoving from $old_path to $new_path";
        if(!move($old_path,$new_path)){
            say "\tcannot move $old_path to $new_path";
            #not recoverable: aborting
            next;
        }

        #chmod(0755,$new_path) is enkel van toepassing op bestanden en mappen direct onder new_path..
        {
            my $command = "chmod -R $rights $new_path && chown -R $uid:$gid $new_path";
            my($stdout,$stderr,$success,$exit_code) = capture_exec($command);

            if(!$success){
                #niet zo erg, valt op te lossen via manuele tussenkomst
                say STDERR $stderr;
            }
        }
        $scan->{path} = $new_path;

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
        

        update_scan($scan);
        update_status($scan,-1);

        #laad op in mediamosa    
        my $command;
        if(is_string($scan->{profile_id}) && $scan->{profile_id} eq "NARA"){
            $command = sprintf(config->{cron}->{register}->{drush_command}->{mmnara},$scan->{path});
        }else{            
             $command = sprintf(config->{cron}->{register}->{drush_command}->{import_directory},$scan->{path});  
        }
        say "\t$command";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
        if(!$success){
            say STDERR $stderr;
        }elsif($stdout =~ /import done. New asset_id: (\w+)/){
            $scan->{asset_id} = $1;
            update_scan($scan);
        }else{
            say STDERR "cannot find asset_id in response";
        }
    }
}


#stap 3: haal lijst uit aleph met alle te scannen objecten en sla die op in 'list' => kan wijzigen, dus STEEDS UPDATEN
say "updating list scans for projects";
my @project_ids = ();
projects()->each(sub{ 
    push @project_ids,$_[0]->{_id}; 
});

foreach my $project_id(@project_ids){

    my $project = projects()->get($project_id);

    my $query = $project->{query};
    next if !$query;

    my @list = ();

    my $meercat = meercat();

    my($offset,$limit,$total) = (0,1000,0);

    my $fetch_successfull = 1;
    try{
        do{

            my $res = $meercat->search($query,{start => $offset,rows => $limit});
            $total = $res->content->{response}->{numFound};
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

        }while($offset < $total);

    }catch{
        $fetch_successfull = 0;
        say STDERR $_;
    };
    if($fetch_successfull){
        say "storing new object list to database";
        $project->{list} = \@list;
        $project->{datetime_last_modified} = Time::HiRes::time;
        projects()->add($project);
        project2index($project);
    }
};
{
    my($success,$error) = index_project->commit;   
    die(join('',@$error)) if !$success;
}


#stap 4: ken scans toe aan projects
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

say "$this_file ended at ".local_time;
