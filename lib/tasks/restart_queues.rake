# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :restart_queues do
  task :now => :environment do
    # All objects to search

    start_time = Time.now
    Rails.logger.info "Start restart_queues at #{start_time.strftime('%H:%M:%S')}..."

    require 'socket'

    # Don't restart queues at the same moment
    sleep 60 if Socket.gethostname == 'queues02.newsworthy.io'

    system 'service monit stop || true'

    exec_jobs('stop')
    exec_jobs('start')

    system 'service monit start'

    Rails.logger.info "Updated restart_queues in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end

private

def exec_jobs(type)
  cmd = []
  Settings.pools.each do |k,v|
    (1..v).map do |p|
      args = "--queue=#{k} --identifier=#{Socket.gethostname}_#{k}_#{p} --pid-dir=#{Rails.root}/tmp/pids"
      cmd << "RAILS_ENV=#{Rubber.env} bundle exec bin/delayed_job #{args} #{type}"
    end
  end
  exec = "sudo -H -u app bash -l -c '#{cmd.join(' && ')}'"
  Rails.logger.info "Exec: #{exec}"
  system exec
end
