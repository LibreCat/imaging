package Imaging::Util;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use File::Basename;
use File::MimeInfo;
use File::Find;
use File::Pid;
use Exporter qw(import);

my @export_files = qw(file_info mtime_latest_file mtime can_delete_file write_to_baginfo);
my @export_data = qw(data_at);
my @export_lock = qw(acquire_lock release_lock check_lock);
our @EXPORT_OK = (@export_files,@export_data,@export_lock);
our %EXPORT_TAGS = (
  files => \@export_files,
  data => \@export_data,
  "lock" => \@export_lock
);

sub _data_at {
  my($val,@keys) = @_;
  my($key) = @keys;
  if(scalar(@keys) > 1){
    if(is_natural($key)){
      if(is_array_ref($val) && $key <= scalar(@$val)){
        shift @keys;
        return _data_at($val->[$key],@keys);
      }else{
        return undef;
      }
    }
    elsif(is_hash_ref($val)){
      shift @keys;
      return _data_at($val->{$key},@keys);
    }else{
      return undef;
    }

  }elsif(scalar(@keys) > 0){
    if(is_natural($key) && is_array_ref($val)){
      return ($key <= scalar(@$val) ) ? $val->[$key]:undef;
    }elsif(is_hash_ref($val)){
      return $val->{$key};
    }else{
      return undef;
    }
  }else{
    return $val;
  }

}
sub data_at {
  my($val,$test) = @_;
  _data_at($val,defined $test ? split(/\./o,$test) : qw());
}
sub file_info {
  my $path = shift;
  my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=lstat($path);
  if($dev){
    return {
      name => basename($path),
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
      name => basename($path),
      path => $path,
      error => $!
    }
  }
}
sub mtime {
  (lstat(shift))[9];
}
sub mtime_latest_file {
  my $dir = shift;
  my $max_mtime = 0;
  my $latest_file;
  find({
    wanted => sub{
      my $mtime = mtime($_);
      if($mtime > $max_mtime){
        $max_mtime = $mtime;
        $latest_file = $_;
      }
    },
    no_chdir => 1
  },$dir);
  return $max_mtime;
}

sub can_delete_file {
  my $file = shift;
  return unless is_string($file);
  return unless (-f $file || -d $file || -l $file);
  if(-f $file || -l $file){
    return -w dirname($file);
  }else{
    return unless -w dirname($file);
    return unless -w $file;
    my @directories = <$file/*>;
    for(@directories){
      my $ok = can_delete_file($_);
      return unless $ok;
    }
  }
  return 1;
}
sub check_lock {
  my $pidfile = shift;
  my $pid = File::Pid->new({ file => $pidfile });
  if(-f $pid->file && $pid->running){
    die("Could not acquire lock at $pidfile. Process ".$pid->pid." is still running");
  }
  $pid;
}
sub acquire_lock {
  my $pidfile = shift;
  my $pid = check_lock($pidfile);
  #plaats lock
  -f $pidfile && ($pid->remove or die("Could not remove lockfile $pidfile"));
  $pid->pid($$);
  $pid->write or die("Could not write lock at $pidfile\n");
}
sub release_lock {
  File::Pid->new({ file => $_[0] })->remove;
}
sub write_to_baginfo {
  my($path,$baginfo)=@_;
  open my $fh,">:encoding(UTF-8)",$path or die($!);
  for my $key(sort keys %$baginfo){
    print $fh sprintf("%s: %s\r\n",$key,$_) for(@{ $baginfo->{$key} });
  }
  close $fh;
}

1;
