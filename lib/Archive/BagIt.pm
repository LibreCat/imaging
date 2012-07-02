package Archive::BagIt::Payload;
use Moose;
use IO::String;
use File::Slurp;

has 'name' => (
    is     => 'rw',
    isa    => 'Str',
);

has 'data' => (
    is     => 'rw',
    isa    => 'ScalarRef[Str]|FileHandle',
);

sub is_io {
    my $self = shift;

    ref($self->data) =~ /^IO/ ? 1 : 0;
}

sub fh {
    my $self = shift;

    $self->is_io ? $self->data : IO::String->new($self->data);
}

sub scalar_ref {
    my $self = shift;
   
    $self->fh->seek(0,0);
    read_file($self->fh, binmode => ':raw', scalar_ref => 1);
}

package Archive::BagIt;
use Moose;
use Encode;
use Digest::MD5;
use IO::File qw();
use List::MoreUtils qw(first_index uniq);
use File::Path qw(remove_tree mkpath);
use File::Slurp qw(read_file write_file);
use POSIX qw(strftime);

has '_error' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[Str]',
    default  => sub { [] },
    init_arg => undef,
    handles  => {
        '_push_error' => 'push' ,
        'errors' => 'elements'
    }
);

has 'dirty' => (
    is       => 'ro',
    isa      => 'Bool',
    writer   => '_dirty',
    default  => 0,
);

has 'path' => (
    is       => 'ro',
    isa      => 'Str',
    writer   => '_path',
    init_arg => undef,
);

has 'version' => (
    is       => 'ro',
    isa      => 'Str',
    writer   => '_version',
    default  => '0.96',
    init_arg => undef,
);

has 'encoding' => (
    is       => 'ro',
    isa      => 'Str',
    writer   => '_encoding',
    default  => 'UTF-8',
    init_arg => undef,
);

has '_tags' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[Str]',
    default  => sub { [] },
    init_arg => undef,
    handles  => {
        'list_tags' => 'elements' ,
    },
);

has '_files' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[Archive::BagIt::Payload]',
    default  => sub { [] },
    init_arg => undef,
    handles  => {
        'list_files' => 'elements' ,
    },
);

has '_fetch' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef',
    default  => sub { [] },
    init_arg => undef,
    handles  => {
        'list_fetch' => 'elements' ,
    },
);

has '_tag_sums' => (
    traits   => ['Hash'],
    isa      => 'HashRef[Str]',
    is       => 'rw',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        'get_tagsum'  => 'get' ,
        'list_tagsum' => 'kv' ,
    },
);

has '_sums' => (
    traits   => ['Hash'],
    isa      => 'HashRef[Str]',
    is       => 'rw',
    default  => sub { {} },
    init_arg => undef,
    handles  => {
        'get_checksum'  => 'get' ,
        'list_checksum' => 'kv' ,
    },
);

has '_info' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef',
    default  => sub { [] },
    init_arg => undef,
);

sub BUILD {
    my $self = shift;

    $self->_update_info;
    $self->_update_tag_manifest;
    $self->_tags([qw(
            bagit.txt
            bag-info.txt
            manifest-md5.txt
            )]);
}

sub read {
    my ($self,$path) = @_;

    $self->_error([]);

    die "usage read(path)" unless $path;

    if (! -d $path ) {
        $self->_push_error("$path doesn't exist");
        return;
    }

    $self->_path($path);

    my $ok = 0;

    $ok += $self->_read_version($path);
    $ok += $self->_read_info($path);
    $ok += $self->_read_tag_manifest($path);
    $ok += $self->_read_manifest($path);
    $ok += $self->_read_tags($path);
    $ok += $self->_read_files($path); 
    $ok += $self->_read_fetch($path);

    $self->_dirty(0);

    $ok == 7;
}

sub write {
    my ($self,$path,%opts) = @_;

    $self->_error([]);

    die "usage write(path[, overwrite => 1])" unless $path;

    remove_tree($path) if $opts{overwrite};

    if (-d $path) {
        $self->_push_error("$path bestaat reeds");
        return undef;
    }

    mkdir $path;

    $self->_path($path);

    my $ok = 0;

    $ok += $self->_write_bagit($path);
    $ok += $self->_write_info($path);
    $ok += $self->_write_data($path);
    $ok += $self->_write_manifest($path);
    $ok += $self->_write_tag_manifest($path);

    $self->_dirty(0);

    $ok == 5;
}

sub add_file {
    my ($self, $name, $data, %opts) = @_;

    if ($opts{overwrite}) {
        $self->remove_file($name);
    }

    $self->_error([]);

    if ($self->get_checksum("$name")) {
        $self->_push_error("$name bestaat reeds in bag");
        return;
    } 

    push @{ $self->_files } , Archive::BagIt::Payload->new(name => $name , data => $data);

    my $sum = $self->_md5_sum($data);

    $self->_sums->{"$name"} = $sum;

    $self->_update_info;
    $self->_update_tag_manifest;

    $self->_dirty(1);

    1;
}

sub remove_file {
    my ($self, $name) = @_;

    $self->_error([]);

    unless ($self->get_checksum($name)) {
        $self->_push_error("$name bestaat niet in bag");
        return;
    }

    my $idx = first_index { $_->{name} eq $name } @{ $self->_files };

    unless ($idx != -1) {
        $self->_push_error("$name bestaat niet in bag");
        return;
    }

    delete $self->_files->[$idx];
    delete $self->_sums->{$name};

    $self->_update_info;
    $self->_update_tag_manifest;

    $self->_dirty(1);

    1;
}

sub _update_info {
    my $self = shift;

    # Add some goodies to the info file...
    $self->add_info('Payload-Oxum',$self->payload_oxum);
    $self->add_info('Bag-Size',$self->size);
    $self->add_info('Bagging-Date', strftime "%Y-%m-%d", gmtime);
}

sub _update_tag_manifest {
    my $self = shift;

    {
        my $sum = $self->_md5_sum($self->_bagit_as_string);
        $self->_tag_sums->{'bagit.txt'} = $sum;
    }

    {
        my $sum = $self->_md5_sum($self->_baginfo_as_string);
        $self->_tag_sums->{'bag-info.txt'} = $sum;
    }

    {
        my $sum = $self->_md5_sum($self->_manifest_as_string);
        $self->_tag_sums->{'manifest-md5.txt'} = $sum;
    }

    if ($self->list_fetch) {
        my $sum = $self->_md5_sum($self->_fetch_as_string);
        $self->_tag_sums->{'fetch.txt'} = $sum;

        unless (grep {/fetch.txt/} $self->list_tags) {
            push @{$self->_tags} , 'fetch.txt';
        }
    }
}

sub add_fetch {
    my ($self, $url, $size, $filename) = @_;
    my (@old) = grep { $_->{filename} ne "data/$filename"} @{$self->_fetch};

    $self->_fetch(\@old);

    push  @{$self->_fetch} , { url => $url , size => $size , filename => "data/$filename" };

    $self->_update_tag_manifest;

    $self->_dirty(1);

    1;
}

sub remove_fetch {
    my ($self, $filename) = @_;
    my (@old) = grep { $_->{filename} ne "data/$filename"} @{$self->_fetch};

    $self->_fetch(\@old);

    $self->_dirty(1);

    1;
}

sub add_info {
    my ($self,$name,$values) = @_;
    my (@old) = grep { $_->[0] ne $name} @{$self->_info};

    $self->_info(\@old);

    if (ref($values) eq 'ARRAY') {
        foreach my $value (@$values) {
            push  @{$self->_info} , [ $name , $value ];
        }
    }
    else {
        push  @{$self->_info} , [ $name , $values ];
    }

    $self->_update_tag_manifest;

    $self->_dirty(1);

    1;
}

sub list_info_tags {
    my ($self) = @_;
    uniq map { $_->[0] } @{$self->_info};
}

sub list_info {
    my ($self,$field) = @_;

    die "usage: list_info(field)" unless $field;

    my @res = map { $_->[1] } grep { $_->[0] eq $field } @{$self->_info};

    wantarray ? @res : join "; ", @res;
}

sub _size {
    my $self = shift;
    my $path = $self->path;

    my $total= 0;

    foreach my $item ($self->list_files) {
        my $size;
        if ($item->is_io && $item->data->can('stat')) {
            $size = [ $item->data->stat ]->[7];
        }
        else {
            $size = length(${$item->data});
        }
        $total += $size;
    }

    $total;
}

sub size {
    my $self = shift;
    my $total = $self->_size;

    if ($total > 100*1024**3) {
        # 100's of GB
        sprintf "%-.3f TB" , $total/(1024**4);
    }
    elsif ($total > 100*1024**2) {
        # 100's of MB
        sprintf "%-.3f GB" , $total/(1024**3);
    }
    elsif ($total > 100*1024) {
        # 100's of KB
        sprintf "%-.3f MB" , $total/(1024**2);
    }
    else {
        sprintf "%-.3f KB" , $total/1024;
    }
}

sub payload_oxum {
    my $self = shift;

    my $size  = $self->_size;
    my $count = $self->list_files;

    return "$size.$count";
}

sub complete {
    my $self = shift;
    my $path = $self->path || '';

    $self->_error([]);

    unless ($self->version and $self->version =~ /^\d+\.\d+$/) {
        $self->_push_error("Tag 'BagIt-Version' niet aanwezig in bagit.txt");       
    }

    unless ($self->encoding and $self->encoding eq 'UTF-8') {
        $self->_push_error("Tag 'Tag-File-Character-Encoding' niet aanwezig in bagit.txt");     
    }

    my @missing = ();

    foreach my $sum ($self->list_checksum) {
        my $file = $sum->[0];
        unless (grep { (my $name = $_->{name} || '') =~ /^$file$/ } $self->list_files) {
            push @missing , $file;          
        }
    }

    foreach my $sum ($self->list_tagsum) {
        my $file = $sum->[0];
        unless (grep { /^$file$/ } $self->list_tags) {
            push @missing  , $file;
        }
    }

    foreach my $file (@missing) {
        unless (grep { $_->{filename} =~ /^$file$/ } $self->list_fetch) {
            $self->_push_error("bestand $file ontbreekt in bag en fetch.txt");
        }
    }

    $self->errors == 0;
}

sub valid {
    my $self = shift;

    my $validator = sub {
        my ($file, $tag) = @_;
        my $path = $self->path;

        # To keep things very simple right now we require at least the
        # bag to be serialized somewhere before we start our validation process
        unless (defined $path && -d $path) {
            return (0,"sorry, enkel geserialiseerde bags worden toegelaten");
        }

        my $md5 = $tag == 0 ? $self->get_checksum($file) : $self->get_tagsum($file);
        my $fh  = $tag == 0 ? new IO::File "$path/data/$file", "r" : new IO::File "$path/$file" , "r";
    
        unless ($fh) {
          return (0,"kan bestand $file niet lezen");
        }

        binmode($fh);

        my $md5_check = $self->_md5_sum($fh);

        undef $fh;

        unless ($md5 eq $md5_check) {
          return (0, "$file checksum faalde $md5 <> $md5_check");
        }

        (1);
    };
    
    $self->_error([]);

    if ($self->dirty) {
        $self->_push_error("bag is dirty : first serialize (write) then try again");
        return 0;
    }
    foreach my $sum ($self->list_checksum) {
       my $file = $sum->[0];
       my ($code,$msg) = $validator->($file,0);

       if ($code == 0) {
        $self->_push_error("$file faalde : $msg");
       }
    }
    foreach my $sum ($self->list_tagsum) {
       my $file = $sum->[0];
       my ($code,$msg) = $validator->($file,1);

       if ($code == 0) {
        $self->_push_error($msg);
       }
    }

    $self->errors == 0;
}

sub _read_fetch {
    my ($self, $path) = @_;

    $self->_fetch([]);

    return 1 unless -f "$path/fetch.txt";

    foreach my $line (read_file("$path/fetch.txt")) {
    $line =~ s/\r\n$/\n/g;
        chomp($line);

        my ($url,$size,$filename) = split(/\s+/,$line,3);

        $filename =~ s/^data\///;

        push @{ $self->_fetch } , { url => $url , size => $size , filename => $filename };
    }

    1;
}

sub _read_tag_manifest {
    my ($self, $path) = @_;

    $self->_tag_sums({});

    if (! -f "$path/tagmanifest-md5.txt") {
        return 1;
    }

    foreach my $line (read_file("$path/tagmanifest-md5.txt")) {
    $line =~ s/\r\n$/\n/g;
        chomp($line);
        my ($sum,$file) = split(/\s+/,$line,2);
        $self->_tag_sums->{$file} = $sum;
    }

    1;
}


sub _read_manifest {
    my ($self, $path) = @_;

    $self->_sums({});

    if (! -f "$path/manifest-md5.txt") {
        $self->_push_error("$path/manifest-md5.txt bestaat niet");
        return;
    }

    foreach my $line (read_file("$path/manifest-md5.txt")) {
    $line =~ s/\r\n$/\n/g;
        chomp($line);
        my ($sum,$file) = split(/\s+/,$line,2);
        $file =~ s/^data\///;
        $self->_sums->{$file} = $sum;
    }

    1;
}

sub _read_tags {
    my ($self, $path) = @_;

    $self->_tags([]);

    local(*F);
    open(F,"find $path -maxdepth 1 -type f |") || die "kan tag-bestanden niet vinden";
    while(<F>) {
    $_ =~ s/\r\n$/\n/g;
        chomp($_);
        $_ =~ s/^$path.//;

        next if $_ =~ /^tagmanifest-\w+.txt$/;

        push @{ $self->_tags } , $_;
    }
    close(F);

    1;
}

sub _read_files {
    my ($self, $path) = @_;

    $self->_files([]);

    if (! -d "$path/data" ) {
        $self->_push_error("payload directory $path/data bestaat niet");
        return;
    }


    local(*F);
    open(F,"find $path/data -type f |") || die "payload directory bevat geen bestanden";

    while(my $file = <F>) {
    $file =~ s/\r\n$/\n/g;
        chomp($file);
        my $name = $file;
        $name =~ s/^$path\/data\///;

#        my $data = read_file($file, binmode => ':raw', scalar_ref => 1);
        my $data = IO::File->new($file);

        push @{ $self->_files } , Archive::BagIt::Payload->new(name => $name, data => $data);
    }

    close(F);

    1;
}

sub _read_info {
    my ($self, $path) = @_;

    $self->_info([]);

    my $info_file = -f "$path/bag-info.txt" ? "$path/bag-info.txt" :  "$path/package-info.txt";

    if (! -f $info_file) {
        $self->_push_error("$path/package-info.txt of $path/bag-info.txt bestaat niet");
        return;
    }

    foreach my $line (read_file($info_file)) {
    $line =~ s/\r\n$/\n/g;
        chomp($line);

        # File::Slurp can't set binmode(':utf8') we need to do it ourselves...
        $line = decode_utf8($line);

        if ($line =~ /^\s+/) {
            $line =~ s/^\s*//;
            $self->_info->[-1]->[1] .= $line;
            next;
        }

        my ($n,$v) = split(/\s*:\s*/,$line,2);

        push @{ $self->_info } , [ $n , $v ];
    }

    1;
}

sub _read_version {
    my ($self, $path) = @_;

    if (! -f "$path/bagit.txt" ) {
        $self->_push_error("$path/bagit.txt bestaat niet");
        return;
    }

    foreach my $line (read_file("$path/bagit.txt")) {
    $line =~ s/\r\n$/\n/g;
        chomp($line);
        my ($n,$v) = split(/\s*:\s*/,$line,2);

        if ($n eq 'BagIt-Version') {
            $self->_version($v);
        }
        elsif ($n eq 'Tag-File-Character-Encoding') {
            $self->_encoding($v);
        }
    }

    1;
}

sub _write_bagit {
    my ($self,$path) = @_;

    local (*F);
    unless (open(F,">:utf8" , "$path/bagit.txt")) {
        $self->_push_error("kon $path/bagit.txt niet aanmaken: $!");
        return;
    }

    printf F $self->_bagit_as_string;
    
    close (F);

    1;
}

sub _bagit_as_string {
    my $self = shift;

    my $version  = $self->version;
    my $encoding = $self->encoding;

    return <<EOF;
BagIt-Version: $version 
Tag-File-Character-Encoding: $encoding 
EOF
}

sub  _write_info {
    my ($self,$path) = @_;

    local(*F);

    unless (open(F,">:utf8", "$path/bag-info.txt")) {
        $self->_push_error("kon $path/bag-info.txt niet aanmaken: $!");
        return;
    }

    print F $self->_baginfo_as_string;

    close(F);

    1;
}

sub _baginfo_as_string {
    my $self = shift;

    my $str = '';

    foreach my $tag ($self->list_info_tags) {
        my @values = $self->list_info($tag);
        foreach my $val (@values) {
            my @msg = split //, "$tag: $val";

            my $cnt = 0;
            while (my (@chunk) = splice(@msg,0,$cnt == 0 ? 79 : 78)) {
                $str .= ($cnt == 0 ? '' : ' ') . join('',@chunk) . "\n";
                $cnt++;
            } 
        }
    }

    $str;
}

sub  _write_data {
    my ($self,$path) = @_;

    unless (mkdir "$path/data") {
        $self->_push_error("kon payload directory $path/data niet aanmaken: $!");
        return;
    }

    foreach my $item ($self->list_files) {
        my $name = 'data/' . $item->{name};
        my $dir  = $name; $dir =~ s/\/[^\/]+$//;

        mkpath("$path/$dir");

        if ($item->is_io) {
            use File::Copy;
            $item->fh->seek(0,0) if $item->data->can('seek');
            copy($item->fh, "$path/$name") || die "failed : $!";
        }
        else {
            write_file("$path/$name", { binmode => ':raw'} , $item->data);
        }
    }

    1;
}

sub _write_fetch {
    my ($self,$path) = @_;

    return 1 unless $self->_fetch > 0;

    local(*F);

    unless (open(F,">:utf8", "$path/fetch.txt")) {
        $self->_push_error("kon $path/fetch.txt niet aanmaken: $!");
        return; 
    }

    print F $self->_fetch_as_string;

    close (F);

    1;
}

sub _fetch_as_string {
    my $self = shift;

    my $str = '';

    foreach my $f ($self->list_fetch) {
        $str .= sprintf "%s %s data/%s\n" , $f->{url}, $f->{size}, $f->{filename};
    }

    $str;
}

sub  _write_manifest {
    my ($self,$path) = @_;

    local (*F);

    unless (open(F,">:utf8", "$path/manifest-md5.txt")) {
        $self->_push_error("kon $path/manifest-md5.txt niet aanmaken: $!");
        return;
    }

    print F $self->_manifest_as_string;

    close(F);
}

sub _manifest_as_string {
    my $self = shift;

    my $str = '';

    foreach my $sum ($self->list_checksum) {
        my $file = $sum->[0];
        my $md5  = $sum->[1];
        $str .= "$md5 data/$file\n";
    }

    $str;
}

sub  _write_tag_manifest {
    my ($self,$path) = @_;

    local (*F);

    unless (open(F,">:utf8", "$path/tag-manifest-md5.txt")) {
        $self->_push_error("kon $path/manifest-md5.txt niet aanmaken: $!");
        return;
    }

    print F $self->_tag_manifest_as_string;

    close(F);

    1;
}

sub _tag_manifest_as_string {
    my $self = shift;

    my $str = '';

    foreach my $sum ($self->list_tagsum) {
        my $file = $sum->[0];
        my $md5  = $sum->[1];
        print F "$md5 $file\n";
    }

    $str;
}

sub _md5_sum {
    my ($self, $data) = @_;

    my $ctx = Digest::MD5->new;

    if (! ref $data) {
        return $ctx->add($data)->hexdigest;
    }
    elsif (ref $data eq 'SCALAR') {
        return $ctx->add($$data)->hexdigest;
    }
    else {
        return $ctx->addfile($data)->hexdigest;
    }
}

no Moose;

1;

=head1 SYNOPSIS

 use Archive::BagIt;

 my $bag = new Archive::BagIt;

 $bag->read('t/bag');

 $bag->version    # 0.96
 $bag->encoding   # UTF-8

 foreach my $payload ($bag->list_files) {
    print $payload->name , "\n";
    
    my $fh = $payload->fh;

    while (<$fh>) {
    }
 }

 $bag->get_checksum('myfile.txt');

