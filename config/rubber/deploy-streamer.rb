namespace :rubber do

  namespace :streamer do

    rubber.allow_optional_tasks(self)

    after 'deploy:stop', 'rubber:streamer:kill'
    after 'deploy:start', 'rubber:streamer:start'
    after 'deploy:restart', 'rubber:streamer:restart'

    before 'deploy:stop', 'rubber:streamer:stop'
    after 'deploy:start', 'rubber:streamer:start'

    def script_path
      'bin/streamer'
    end

    desc 'Stop the streamer process'
    task :stop, :roles => :streamer do
      rsudo "cd #{current_path} && RAILS_ENV=#{Rubber.env} bundle exec #{self.script_path} stop", :as => rubber_env.app_user
    end

    desc 'Start the streamer process'
    task :start, :roles => :streamer do
      rsudo 'pkill -9 -f [s]treamer- || true'
      rsudo "rm -r -f #{rubber_env.streamer_pid_dir}/streamer-*"
      rsudo "cd #{current_path} && RAILS_ENV=#{Rubber.env} bundle exec #{self.script_path} start", :as => rubber_env.app_user
    end

    desc 'Restart the streamer process'
    task :restart, :roles => :streamer do
      rsudo "cd #{current_path} && RAILS_ENV=#{Rubber.env} bundle exec #{self.script_path} stop", :as => rubber_env.app_user
      rsudo 'pkill -9 -f [s]treamer- || true'
      rsudo "rm -r -f #{rubber_env.streamer_pid_dir}/streamer-*"
      rsudo "cd #{current_path} && RAILS_ENV=#{Rubber.env} bundle exec #{self.script_path} start", :as => rubber_env.app_user
    end

    desc 'Forcefully kills the streamer process'
    task :kill, :roles => :streamer do
      rsudo 'pkill -9 -f [s]treamer- || true'
      rsudo "rm -r -f #{rubber_env.streamer_pid_dir}/streamer-*"
    end

    desc 'Display status of the streamer process'
    task :status, :roles => :streamer do
      rsudo 'ps -eopid,user,cmd | grep streamer || true'
    end

    desc 'Live tail of streamer log files for all machines'
    task :tail_logs, :roles => :streamer do
      last_host = ''
      log_file_glob = rubber.get_env('FILE', 'Log files to tail', true, "#{current_path}/log/streamer.output")
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
