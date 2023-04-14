# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :backup do
  task :db => :environment do
    start_time = Time.now
    Rails.logger.info "Start backup:db at #{start_time.strftime('%H:%M:%S')}..."

    config = YAML::load(File.open("#{Rails.root}/config/mongoid.yml"))[Rails.env]['clients']['default']

    host = config['hosts'].first.split(':').first
    database = config['database']
    user = (Settings.db ? Settings.db.backup.user : nil)
    password = (Settings.db ? Settings.db.backup.password : nil)

    tmpdir = Dir.mktmpdir
    filename = "#{database}-#{Date.today.month}-#{Date.today.day}-#{Date.today.year}.tar.gz"
    dump = "#{tmpdir}/#{filename}"

    begin
      dump_database(tmpdir, database, host, user, password)
      compress_dump(tmpdir, dump, database)
      upload_to_glacier(dump, database)
      upload_to_s3(dump, database, filename)
    rescue Exception => e
      ApplicationController.error(Rails.logger, "Fail dumping db for #{dump}", e)
      p e
    end

    FileUtils.rm_rf(tmpdir)

    Rails.logger.info "Task backup:db finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :ebs => :environment do
    start_time = Time.now
    Rails.logger.info "Start backup:ebs at #{start_time.strftime('%H:%M:%S')}..."

    require 'fog'

    aws = Fog::Compute.new(provider: 'AWS', aws_access_key_id: Settings.aws.access_key_id, aws_secret_access_key: Settings.aws.secret_key)
    date = "#{Date.today.month}-#{Date.today.day}-#{Date.today.year}"

    begin
      aws.describe_instances.body['reservationSet'].map do |i|
        i = i['instancesSet'].first
        if i['tagSet']['Environment'] == 'production'
          Rails.logger.info "Backup instance #{i['tagSet']['Name']} (#{i['instanceId']})"
          i['blockDeviceMapping'].map do |v|
            begin
              Rails.logger.info "     | volume #{v['volumeId']} (#{i['instanceId']})"
              snapshot = aws.snapshots.new
              snapshot.description = "Backup of #{i['tagSet']['Name']} (#{i['instanceId']}) on #{date}"
              snapshot.volume_id = v['volumeId']
              snapshot.save
              snapshot.wait_for { reload.id rescue nil }
              id = snapshot.reload.id
              aws.tags.create(resource_id: id, key: 'Environment', value: 'production')
              aws.tags.create(resource_id: id, key: 'Date', value: date)
            rescue Exception => e
              ApplicationController.error(Rails.logger, "Fail taking snapshot for volume #{v['volumeId']} (#{i['instanceId']})", e)
            end
          end
        end
      end
    rescue Exception => e
      ApplicationController.error(Rails.logger, 'Fail taking snapshot', e)
    end

    Rails.logger.info "Task backup:ebs finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  def dump_database(tmpdir, database, host, user, password)
    require 'open3'

    cmd = "/usr/bin/mongodump --db #{database} #{user ? "-u #{user} -p #{password}" : nil} -h #{host} --authenticationDatabase admin -o #{tmpdir}"
    stdout, stderr, status = Open3.capture3(cmd)

    raise Exception.new(stderr) unless status.success?
    raise Exception.new("error dump directory not present: #{stdout} #{stderr}") unless Dir.exist?(File.join(tmpdir, database))
  end

  def compress_dump(tmpdir, dump, database)
    cmd = "/bin/tar zcvf #{dump} #{File.join(tmpdir, database)}"
    stdout, stderr, status = Open3.capture3(cmd)

    raise Exception.new(stderr) unless status.success?
    raise Exception.new("error dump not present: #{stdout} #{stderr}") unless File.exist?(dump)
  end

  def upload_to_glacier(dump, database)
    require 'fog'

    storage = Fog::AWS::Glacier.new(aws_access_key_id: Settings.aws.access_key_id, aws_secret_access_key: Settings.aws.secret_key)
    vault = storage.vaults.create id: "#{Rails.env}_database_#{database}"
    vault.archives.create(body: File.new(dump), multipart_chunk_size: 1024*1024)
  end

  def upload_to_s3(dump, database, filename)
    require 'fog'

    storage = Fog::Storage.new(provider: 'AWS', aws_access_key_id: Settings.aws.access_key_id, aws_secret_access_key: Settings.aws.secret_key)

    directory = storage.directories.create(key: "#{Rails.env}_database_#{database}".gsub('_', '-'))
    directory.files.create(body: File.new(dump), key: filename)
  end
end
