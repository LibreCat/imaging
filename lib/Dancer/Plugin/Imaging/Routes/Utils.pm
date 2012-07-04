package Dancer::Plugin::Imaging::Routes::Utils;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is :array);
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::Strptime;
use Time::HiRes;
use Clone qw(clone);
use Digest::MD5 qw(md5_hex);
use Dancer::Plugin::Database;

sub core {
    state $core = store("core");
}
sub projects { 
    state $projects = core()->bag("projects");
}
sub scans {
    state $scans = core()->bag("scans");
}
sub index_scan {
    state $index_scans = store("index_scan")->bag;
}
sub index_log {
    state $index_log = store("index_log")->bag;
}
sub index_project {
    state $index_project = store("index_project")->bag;
}
sub dbi_handle {
    state $dbi_handle = database;
}
sub formatted_date {
    my $time = shift || Time::HiRes::time;
    DateTime::Format::Strptime::strftime(
        '%FT%T.%NZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}
sub local_time {
    my $time = shift || time;
    $time = int($time);
    DateTime::Format::Strptime::strftime(
        '%FT%TZ', DateTime->from_epoch(epoch=>$time,time_zone => DateTime::TimeZone->new(name => 'local'))
    );
}
sub project2index {
    my $project = shift;
    my $doc = {};
    $doc->{$_} = $project->{$_} foreach(qw(_id name name_subproject description query num_hits));
    foreach my $key(keys %$project){
        next if $key !~ /datetime/o;
        $doc->{$key} = formatted_date($project->{$key});
    }

    my @list = ();
    foreach my $item(@{ $project->{list} || [] }){
        # id: plaatsnummer of rug01 mogelijk (verschil met name: letters verwisseld, en bijkomende nummering mogelijk bij plaatsnummers)
        if($item->{location}){
            my $id = $item->{location};
            $id =~ s/[\.\/]/-/go;
            if(defined($item->{number})){
                $id .= "-".$item->{number};
            }
            push @list,$id;
        }
        push @list,uc($item->{source})."-".$item->{fSYS};
    }
    $doc->{list} = \@list;
    # doc.list.length != project.list.size
    # doc.list => "lijst van mogelijke items"
    # project.list => "lijst van items"
    $doc->{total} = scalar(@{ $project->{list} });
    index_project->add($doc);
}
sub status2index {
    my($scan,$history_index) = @_;
    my $doc;
    my $index_log = index_log();
    my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });

    my $history_objects;
    if(array_exists($scan->{status_history},$history_index)){
        $history_objects = [ $scan->{status_history}->[$history_index] ];
    }else{
        $history_objects = $scan->{status_history};
    }

    foreach my $history(@$history_objects){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{scan_id} = $scan->{_id};
        $doc->{owner} = $user->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
}
sub marcxml_flatten {
    my $xml = shift;
    my $ref = from_xml($xml,ForceArray => 1);
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

    #default doc
    my $doc = clone($scan);

    #metadata
    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} }); 
    $doc->{metadata_id} = \@metadata_ids;
    $doc->{marc} = [];
    push @{ $doc->{marc} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});

    #files
    $doc->{files} = [ map { $_->{path} } @{ $scan->{files} || [] } ];


    #status history
    for(my $i = 0;$i < scalar(@{ $doc->{status_history} });$i++){
        my $item = $doc->{status_history}->[$i];
        $doc->{status_history}->[$i] = $item->{user_login}."\$\$".$item->{status}."\$\$".formatted_date($item->{datetime})."\$\$".$item->{comments};
    }

    #project info
    delete $doc->{project_id};
    if(is_array_ref($scan->{project_id}) && scalar(@{$scan->{project_id}}) > 0){
        foreach my $project_id(@{$scan->{project_id}}){
            my $project = projects->get($project_id);
            next if !is_hash_ref($project);
            foreach my $key(keys %$project){
                next if $key eq "list";
                my $subkey = "project_$key";
                $subkey =~ s/_{2,}/_/go;
                $doc->{$subkey} ||= [];
                push @{$doc->{$subkey}},$project->{$key};
            }
        }
    }

    #user info
    if($scan->{user_id}){
        my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
        if($user){
            my @keys = qw(name login);
            $doc->{"user_$_"} = $user->{$_} foreach(@keys);
            $doc->{user_roles} = [split(',',$user->{roles})];
        }
    }
    
    #convert datetime to iso
    foreach my $key(keys %$doc){
        next if $key !~ /datetime/o;
        if(is_array_ref($doc->{$key})){
            $_ = formatted_date($_) for(@{ $doc->{$key} });
        }else{
            $doc->{$key} = formatted_date($doc->{$key});
        }
    }

    #opkuisen
    my @deletes = qw(metadata comments busy busy_reason warnings new_path new_id new_user);
    delete $doc->{$_} for(@deletes);

    index_scan()->add($doc);
}

register local_time => \&local_time;
register core => \&core;
register scans => \&scans;
register projects => \&projects;
register dbi_handle => \&dbi_handle;
register index_scan => \&index_scan;
register index_log => \&index_log;
register index_project => \&index_project;


register scan2index => \&scan2index;
register status2index => \&status2index;
register project2index => \&project2index;


register_plugin;

__PACKAGE__;
