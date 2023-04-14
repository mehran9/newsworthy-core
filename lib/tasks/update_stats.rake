# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_stats do
  task :all => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating stats at #{start_time.strftime('%H:%M:%S')}..."

    if Utils.get_process_count('rake update_stats:all') > 1
      Rails.logger.warn 'Update stats already in progress. Exiting'
      exit
    end

    models = %w(Article IndustryTweet NetworkTweet Mention MentionIndustryTweet MentionNetworkTweet)

    Parallel.map(models, in_threads: 2) do |c|
      update_stats(c)
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  def update_stats(object_class)
    start_time = Time.now
    Rails.logger.info "-> Start updating stats for #{object_class} at #{start_time.strftime('%H:%M:%S')}..."

    ranges = [
        { key: '1h', value: 1.hour.ago  },
        { key: '2h', value: 2.hours.ago },
        { key: '4h', value: 4.hours.ago },
        { key: '8h', value: 8.hours.ago },
        { key: '1d', value: 1.day.ago   },
        { key: '2d', value: 2.days.ago  },
        { key: '3d', value: 3.days.ago  },
        { key: '1w', value: 1.week.ago  },
        { key: '2w', value: 2.weeks.ago },
        { key: '1m', value: 1.month.ago },
        { key: '3m', value: 3.months.ago }
    ]

    elem = 0
    objects = []
    fields = :tweets, :sentiment_score, ranges.flat_map{|r| %W(stats_#{r[:key]} sentiment_score_#{r[:key]} sentiment_score_all) }
    object_class.constantize.only(fields).where(:_created_at.gte => ranges.last[:value]).map do |a|
      obj = {}

      unless a['tweets'].blank?
        ranges.map do |r|
          stat = 0
          a['tweets'].map do |t|
            begin
              stat += 1 if Time.parse(t['last_tweet_date']) >= r[:value]
            rescue
              0
            end
          end

          next if a["stats_#{r[:key]}"] == stat # Same count, skip update

          # Calculate stats for #{a['objectId']} in stat_#{r[:key]} row with count #{count}
          obj["stats_#{r[:key]}"] = stat
        end
      end

      unless a['sentiment_score'].blank?
        ranges.map do |r|
          stat = Utils.get_avg_score(a['sentiment_score'], r[:value])

          next if a["sentiment_score_#{r[:key]}"] == stat # Same count, skip update

          # Calculate stats for #{a['objectId']} in stat_#{r[:key]} row with count #{count}
          obj["sentiment_score_#{r[:key]}"] = stat
        end

        stat = Utils.get_avg_score(a['sentiment_score'])

        next if a['sentiment_score_all'] == stat # Same count, skip update

        # Calculate stats for #{a['objectId']} in stat_#{r[:key]} row with count #{count}
        obj['sentiment_score_all'] = stat
      end

      unless obj.blank?
        elem += 1
        objects << { update_one: { filter: { _id: a.id }, update: { '$set' => obj }}}
      end
    end

    if objects.count > 0
      object_class.constantize.collection.bulk_write(objects)
    end

    Rails.logger.info "-> Updated stats for #{elem} #{object_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}"
  end
end
