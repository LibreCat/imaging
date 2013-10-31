dirs="/mnt/data01/01_ready /mnt/data01/02_imaging /mnt/data01/03_grep/process-in /mnt/data01/03_grep/ingest-in /mnt/data01/03_grep/ingest-accepted"

for dir in $dirs;
do
  find $dir -type f -exec ls -ld {} \;
done;
