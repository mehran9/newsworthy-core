# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_tl do
  task :info => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating tls at #{start_time.strftime('%H:%M:%S')}..."

    ThoughtLeader.only(:twitter_id).where(profile_updated_at: 1.month.ago, disable: false).pluck(:twitter_id).map do |t|
      UpdateTl.perform_later(t, 'ThoughtLeader')
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :score => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating tls score at #{start_time.strftime('%H:%M:%S')}..."

    %w(ThoughtLeader MentionedPerson).map do |c|
      c.constantize.only(:id).pluck(:id).map do |t|
        UpdateScores.perform_later(t, c)
      end
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :all => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating TL and MP info at #{start_time.strftime('%H:%M:%S')}..."

    %w(ThoughtLeader MentionedPerson).map do |c|
      c.constantize.only(:twitter_id).pluck(:twitter_id).map do |t|
        UpdateTl.perform_later(t, c)
      end
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
