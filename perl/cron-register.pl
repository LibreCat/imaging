#!/usr/bin/env perl
use Catmandu qw(store);
use Dancer qw(:script);
use Imaging::Util;

use Catmandu::Sane;
use Catmandu::Util qw(require_package :is);
use List::MoreUtils qw(first_index);
use File::Basename qw();
use File::Copy qw(copy move);
use Cwd qw(abs_path);
use File::Spec;
use Try::Tiny;
use Digest::MD5 qw(md5_hex);
use Time::HiRes;
use File::MimeInfo;

BEGIN {
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
}
use Dancer::Plugin::Imaging::Routes::Utils;
use Dancer::Plugin::Imaging::Routes::Meercat;


#variabelen
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
sub mount_conf {
    config->{mounts}->{directories} ||= {};
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
    die($error) if !$success;
}
#stap 2: ken scans toe aan projects
say "assigning scans to projects";
my @scan_ids = ();
scans->each(sub{ push @scan_ids,$_[0]->{_id}; });
foreach my $scan_id(@scan_ids){
    my $scan = scans->get($scan_id);
    my $result = index_project->search(query => "list:\"".$scan->{_id}."\"",limit => 1000);
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
    die($error) if !$success;
}

#stap 3: haal metadata op (alles met incoming_ok of hoger, ook die zonder project) => enkel indien goed bevonden, maar metadata wordt slechts EEN KEER opgehaald
#wijziging/update moet gebeuren door qa_manager
say "retrieving metadata for good scans";
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
    if($query =~ /^RUG\d{2}-/o){
        $query =~ s/^RUG(\d{2})-/rug$1:/o;
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
                baginfo => create_baginfo(
                    xml => $doc->{fXML},
                    size => $scan->{size},
                    num_files => scalar(@{$scan->{files}})
                )
            };
        }

    }
    my $num = scalar(@{$scan->{metadata}});
    say "\tscan ".$scan->{_id}." has $num metadata-records";
    scans()->add($scan);
    scan2index($scan);

    my($success,$error) = index_scan->commit;
    die($error) if !$success;
}

#stap 4: registreer scans die 'incoming_ok' zijn, en verplaats ze naar 02_ready (en maak hierbij manifest indien nog niet aanwezig)
my @incoming_ok = ();
scans()->each(sub{
    my $scan = shift;
    push @incoming_ok,$scan->{_id} if $scan->{status} eq "incoming_ok";
});
say "registering incoming_ok";
foreach my $id (@incoming_ok){
    my $scan = scans()->get($id);
    my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
    say "\tscan $id:";

    #status 'registering'
    $scan->{status} = "registering";
    push @{ $scan->{status_history} },{
        user_login =>"-",
        status => "registering",
        datetime => Time::HiRes::time,
        comments => ""
    };
    $scan->{datetime_last_modified} = Time::HiRes::time;
    #=> registratie kan lang duren (move!), waardoor map uit /ready verdwijnt, maar ondertussen ook in /scans is terug te vinden
    #=> daarom opnemen in databank én indexeren
    scans->add($scan);
    scan2index($scan);
    my($success,$error) = index_scan->commit;
    die($error) if !$success;

    status2index($scan,-1);
    ($success,$error) = index_log->commit;
    die($error) if !$success;

    if($user->{profile_id} ne "BAG"){

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
            print MANIFEST "$md5sum_file ".File::Basename::basename($file->{path})."\r\n";
            close FILE;
        }
        close MANIFEST;

        #voeg manifest toe aan de lijst
        push @{ $scan->{files} },file_info($scan->{path}."/manifest.txt");
    
    }
    
    #verplaats  
    my $oldpath = $scan->{path};
    my $mount_conf = mount_conf();
    my $newpath = $mount_conf->{path}."/".$mount_conf->{subdirectories}->{processed}."/".File::Basename::basename($oldpath);
    say "\tmoving from $oldpath to $newpath";
    move($oldpath,$newpath);
    chmod(0755,$newpath);
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
        user_login =>"-",
        status => "registered",
        datetime => Time::HiRes::time,
        comments => ""
    };
    $scan->{datetime_last_modified} = Time::HiRes::time;
    
    scans->add($scan);
    scan2index($scan);
    ($success,$error) = index_scan->commit;
    die($error) if !$success;
    status2index($scan,-1);
    ($success,$error) = index_log->commit;
    die($error) if !$success;
}

index_log->store->solr->optimize();
index_scan->store->solr->optimize();
index_project->store->solr->optimize();

say "$this_file ended at ".local_time;
