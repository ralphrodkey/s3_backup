s3_backup
=========

Simple Ruby utility for incremental backups to S3


Purpose
=========
I needed to handle offsite backup for a small business's NAS, and the built-in software was failing to do the job. Additionally, the location didn't have a ton of bandwidth, and sending several terabytes of data to S3 was making life unlivable for the employees. Thus this little utility was born.

The utility recursively examines the target directory for updated or previously un-encountered files. It uses an SQLite database to keep track of the modification date of all files it encounters. If the database indicates that a file is new or updated, the file is sent to S3. At the end of the backup run, the database is compressed and uploaded to S3. At the start of the next run, the database is downloaded, decompressed, and used as the authoritative index of what's in S3.

The utility doesn't delete files from S3, so any files that are accidentally deleted will still be in S3. It also does not keep multiple versions of files.

Backup sessions can be limited by time. In my case, I wanted to start the backup after everyone was out of the office and stop it before they got there the next morning. This allowed me to gradually back up all data, since each run of the utility would typically encounter a few previously-seen files that needed to be updated, but then spend most of its time in parts of the file tree it hadn't seen before. Every night produced a bit more progress, until everything had been uploaded, at which point modified and new files were the only things being uploaded, resulting in relatively fast backup sessions.

Usage
=========
    s3_backup.rb [source_directory] [time_limit]

source_directory - defaults to "."  
time_limit - unlimited by default. Specified in seconds otherwise.

Sample cron invocation:
    0 21 * * * /home/me/.rvm/wrappers/ruby-2.1.5@s3_backup/ruby /home/me/s3_backup/s3_backup.rb /mnt/my_nas 32400 >/var/log/s3_backup.log 2>&1