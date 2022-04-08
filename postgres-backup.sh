# Database name
db_name=docspelldb ### MAKE SURE THIS IS THE CORRECT DB NAME
# Backup storage directory 
backupfolder=~/postgresql/backups
# Notification email address 
recipient_email=###YOUR-EMAIL-HERE
# Number of days to store the backup 
keep_day=3
sqlfile=$backupfolder/all-database-$(date +%d-%m-%Y_%H-%M-%S).sql
zipfile=$backupfolder/all-database-$(date +%d-%m-%Y_%H-%M-%S).zip
#create backup folder
mkdir -p $backupfolder
# Create a backup
if pg_dump $db_name > $sqlfile ; then
   echo 'Sql dump created'
else
   echo 'pg_dump return non-zero code' | mailx -s 'No backup was created!' $recipient_email
   exit
fi
# Compress backup 
if gzip -c $sqlfile > $zipfile; then
   echo 'The backup was successfully compressed'
else
   echo 'Error compressing backup' | mailx -s 'Backup was not created!' $recipient_email
   exit
fi
rm $sqlfile 
echo $zipfile | mailx -s 'Backup was successfully created' $recipient_email
# Delete old backups 
find $backupfolder -mtime +$keep_day -delete
