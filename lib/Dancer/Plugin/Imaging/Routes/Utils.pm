package Dancer::Plugin::Imaging::Routes::Utils;
use Dancer qw(:syntax);
use Dancer::Plugin;
use Catmandu::Sane;
use Catmandu qw(store);
use Catmandu::Util qw(:is);

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
sub status2index {
    my $scan = shift;
    my $doc;
    my $index_log = index_log();
    my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });

    foreach my $history(@{ $scan->{status_history} || [] }){
        $doc = clone($history);
        $doc->{datetime} = formatted_date($doc->{datetime});
        $doc->{scan_id} = $scan->{_id};
        $doc->{owner} = $user->{login};
        my $blob = join('',map { $doc->{$_} } sort keys %$doc);
        $doc->{_id} = md5_hex($blob);
        $index_log->add($doc);
    }
    $index_log->commit;
    $doc;
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

    my $doc = clone($scan);
    my @metadata_ids = ();
    push @metadata_ids,$_->{source}.":".$_->{fSYS} foreach(@{ $scan->{metadata} }); 
    
    $doc->{text} = [];
    push @{ $doc->{text} },@{ marcxml_flatten($_->{fXML}) } foreach(@{$scan->{metadata}});

    my @deletes = qw(metadata comments busy busy_reason warnings);
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
        my $user = dbi_handle->quick_select("users",{ id => $scan->{user_id} });
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
    
    index_scan()->add($doc);
    index_scan()->commit;
    $doc;
}

register local_time => \&local_time;
register core => \&core;
register scans => \&scans;
register projects => \&projects;
register dbi_handle => \&dbi_handle;
register index_scan => \&index_scan;
register index_log => \&index_log;

register scan2index => \&scan2index;
register status2index => \&status2index;

register_plugin;

__PACKAGE__;
