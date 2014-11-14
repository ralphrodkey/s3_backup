require 'rubygems'
require 'bundler/setup'
require 'aws-sdk'
require 'sqlite3'
require 'tempfile'

AWS_ACCESS_KEY = "ABC"
AWS_SECRET_ACCESS_KEY = "123"
AWS_REGION = "us-east-1"
S3_BUCKET = "my_s3_backups"

def walk_tree(root, &block)
  walk_tree_recursor root, root, block
end

def walk_tree_recursor(root, current_dir, block)
  root = File.absolute_path(root)
  current_dir = File.absolute_path(current_dir)

  Dir.foreach(current_dir) do |entry|
    next if entry == "." || entry == ".."
    entry = File.join(current_dir, entry)

    type = File.ftype(entry)
    if type == "file" then
      block.call root, entry
    elsif type == "directory" then
      walk_tree_recursor root, entry, block
    end
  end
end

def config_s3
  AWS.config(
    :access_key_id => AWS_ACCESS_KEY,
    :secret_access_key => AWS_SECRET_ACCESS_KEY,
    :region => AWS_REGION)
  AWS::S3.new
end

def run(root = ".", run_seconds = -1)
  run_seconds = run_seconds.to_i unless run_seconds.is_a? Fixnum

  puts "Backing up: #{root}"
  puts "Runtime limited to #{run_seconds} seconds" if run_seconds != -1

  start = Time.now

  s3 = config_s3
  bucket = s3.buckets[S3_BUCKET]
  
  db_file = Tempfile.new("s3_backup.sqlite")
  db_file.close

  obj = bucket.objects["s3_backup.sqlite.bz2"]
  if obj.exists?
    compressed_db_file = Tempfile.new("s3_backup.sqlite.bz2")
    compressed_db_file.binmode

    puts "Downloading database"
    obj.read do |chunk|
      compressed_db_file.write(chunk)
    end
    compressed_db_file.close

    puts "Decompressing"
    `/bin/tar -xjOf #{compressed_db_file.path} >#{db_file.path}`
    compressed_db_file.unlink
  else
    puts "Creating new database"
    db = SQLite3::Database.open(db_file.path)
    db.execute "CREATE TABLE IF NOT EXISTS Files(Name TEXT PRIMARY KEY, ModificationDate TEXT)"
    db.close
  end

  db = SQLite3::Database.open(db_file.path)

  walk_tree root do |root, entry|
    if Time.now - start > run_seconds
      puts "Out of time"
      break
    end
    relative_path = entry.sub("#{root}#{File::SEPARATOR}", "")
    mtime = File.mtime(entry).iso8601

    results = db.execute "select * from Files where Name = ?", relative_path
    if results.count == 0 || results[0][1] != mtime
      puts "Uploading #{relative_path}"
      obj = bucket.objects[relative_path]
      obj.write(:file => entry)

      db.execute "insert or replace into Files values(?, ?)", relative_path, mtime
    end
  end

  db.close

  puts "Compressing"
  compressed_db_file = Tempfile.new("s3_backup.sqlite.bz2")
  compressed_db_file.close
  `/bin/tar -cjf #{compressed_db_file.path} #{db_file.path}`
  db_file.unlink

  puts "Uploading database"
  bucket.objects["s3_backup.sqlite.bz2"].write(:file => compressed_db_file.path)
  compressed_db_file.unlink

  puts "Exiting"
end

run(ARGV[0], ARGV[1]) if __FILE__==$0