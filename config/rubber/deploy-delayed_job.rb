namespace :rubber do

  namespace :delayed_job do

    rubber.allow_optional_tasks(self)

    after 'deploy:stop', 'rubber:delayed_job:stop'
    after 'deploy:start', 'rubber:delayed_job:start'
    after 'deploy:restart', 'rubber:delayed_job:restart'

    before 'deploy:stop', 'rubber:monit:stop'
    after 'deploy:start', 'rubber:monit:start'

    def script_path
      bin_path = 'bin/delayed_job'
      script_path = 'script/delayed_job'

      File.exists?(bin_path) ? bin_path : script_path
    end

    def exec_jobs(type)
      cmd = "cd #{current_path}"
      config = "config/settings/#{Rubber.env}.yml"
      pools = File.exists?(script_path) ? YAML::load(File.open(config))['pools'] : []
      pools.each do |k,v|
        (1..v).map do |p|
          args = "--queue='#{k}' --identifier='$HOSTNAME\\_#{k}_#{p}' --pid-dir=#{rubber_env.delayed_job_pid_dir}"
          cmd += " && RAILS_ENV=#{Rubber.env} bundle exec #{self.script_path} #{args} #{type}"
        end
      end
      rsudo cmd, as: rubber_env.app_user
    end

    desc 'Stop the delayed_job process'
    task :stop, :roles => :delayed_job do
      exec_jobs('stop')
    end

    desc 'Start the delayed_job process'
    task :start, :roles => :delayed_job do
      rsudo 'pkill -9 -f [d]elayed_job || true'
      rsudo "rm -r -f #{rubber_env.delayed_job_pid_dir}/delayed_job.*"
      exec_jobs('start')
    end

    desc 'Restart the delayed_job process'
    task :restart, :roles => :delayed_job do
      exec_jobs('stop')
      rsudo 'pkill -9 -f [d]elayed_job || true'
      rsudo "rm -r -f #{rubber_env.delayed_job_pid_dir}/delayed_job.*"
      exec_jobs('start')
    end

    desc 'Forcefully kills the delayed_job process'
    task :kill, :roles => :delayed_job do
      rsudo 'pkill -9 -f [d]elayed_job || true'
      rsudo "rm -r -f #{rubber_env.delayed_job_pid_dir}/delayed_job.*"
    end

    desc 'Display status of the delayed_job process'
    task :status, :roles => :delayed_job do
      rsudo 'ps -eopid,user,cmd | grep [d]elayed_job  || true'
    end

    desc 'Live tail of delayed_job log files for all machines'
    task :tail_logs, :roles => :delayed_job do
      last_host = ''
      log_file_glob = rubber.get_env('FILE', 'Log files to tail', true, "#{current_path}/log/delayed_job_production.log")
      trap('INT') { puts 'Exiting...'; exit 0; }                    # handle ctrl-c gracefully
      run "tail -qf #{log_file_glob}" do |channel, stream, data|
        puts if channel[:host] != last_host                         # blank line between different hosts
        host = "[#{channel.properties[:host].gsub(/\..*/, '')}]"    # get left-most subdomain
        data.lines { |line| puts '%-15s %s' % [host, line] }        # add host name to the start of each line
        last_host = channel[:host]
        break if stream == :err
      end
    end
  end
end
