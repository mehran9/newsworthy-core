# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

namespace :update_tweets do
  task :table => :environment do
    start_time = Time.now
    Rails.logger.info "-> Start tweets at #{start_time.strftime('%H:%M:%S')}..."

    objects = {}
    created_at = 99.years.ago
    run = true
    elem = 0
    while run do
      begin
        Rails.logger.info "   Get the ##{elem} Article. Created at: #{created_at}"
        ret = nil
        Retriable.retriable do
          ret = Parse::Query.new('Article').tap do |q|
            q.limit = 1000
            q.skip = 0
            q.order_by = 'createdAt'
            q.greater_than('createdAt', Parse::Date.new(created_at))
          end.get
        end

        if ret.empty? || ret.count <= 0
          Rails.logger.info "   Find limits for Article: #{ret.count}. Break loop..."
          run = false
        else
          ret.each do |a|
            elem += 1
            next unless a['tweets']

            objects[a.id] = [] unless objects[a.id]

            a['tweets'].map do |t|
              if !t['tweet_id']
                Rails.logger.info " > Find empty tweet id in article #{a.id}"
              elsif objects[a.id].include?(t['tweet_id'])
                Rails.logger.info " > Find similar tweet in article #{a.id}"
              else
                objects[a.id] << t['tweet_id']
              end
            end
          end
          created_at = ret.last['createdAt']
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_tweets:table] Can't fetch Article", e)
      end
    end

    Rails.logger.info "-> Find #{objects.count} articles to update"

    total = objects.count
    Parallel.each_with_index(objects, in_threads: 2) do |o,i|
      article_id = o.first
      tweets = o.last

      Rails.logger.info "   #{i}/#{total} Adding tweet for article #{article_id}..."
      tweets.map do |t|
        add_tweet_to_db(article_id, t)
      end
    end

    Rails.logger.info "-> Updated tweets in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :change => :environment do
    start_time = Time.now
    Rails.logger.info "-> Start tweets at #{start_time.strftime('%H:%M:%S')}..."

    objects = []
    created_at = 99.years.ago
    run = true
    elem = 0
    while run do
      begin
        Rails.logger.info "   Get the ##{elem} Article. Created at: #{created_at}"
        ret = nil
        Retriable.retriable do
          ret = Parse::Query.new('Tweet').tap do |q|
            q.limit = 1000
            q.skip = 0
            q.order_by = 'createdAt'
            q.greater_than('createdAt', Parse::Date.new(created_at))
          end.get
        end

        if ret.empty? || ret.count <= 0
          Rails.logger.info "   Find limits for Article: #{ret.count}. Break loop..."
          run = false
        else
          objects.concat(ret)
          created_at = ret.last['createdAt']
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_tweets:table] Can't fetch Article", e)
      end
    end

    Rails.logger.info "-> Find #{objects.count} articles to update"

    total = objects.count
    Parallel.each_with_index(objects, in_threads: 2) do |o,i|
      Rails.logger.info "   #{i}/#{total} Change tweet type for #{o['tweet_id']}..."
      o['tmp_tweet_id'] = o['tweet_id'].to_s
      Retriable.retriable do
        o.save
      end
    end

    Rails.logger.info "-> Updated tweets in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :array => :environment do
    start_time = Time.now
    Rails.logger.info "-> Start array at #{start_time.strftime('%H:%M:%S')}..."

    models = %w(Article IndustryTweet NetworkTweet Mention MentionIndustryTweet MentionNetworkTweet)

    models.map do |m|
      change_array(m)
    end

    Rails.logger.info "-> Updated array in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def change_array(class_name)
    objects = []

    Rails.logger.info "Change array for class #{class_name}"
    class_name.constantize.only(:tweets).all.map do |o|

      changed = false
      begin
        if o['tweets']
          tweets_ids = []
          users_ids = []
          tweets = []
          o['tweets'].each_with_index do |t, i|


            # if !t['tweets'] or !t['tweets'].is_a?(Array) or t['tweets'].count <= 0
            #   p "Empty array for #{o.id} #{class_name}"
            #   if o['tweets'].count == 1
            #     p "Delete #{o.id} #{class_name}"
            #     class_name.constantize.where(id: o.id).destroy
            #   else
            #     o['tweets'].delete_at(i)
            #     changed = true
            #   endou start working on tasks from the backlog that are assigne
            # end

            # t.delete_if{|m| m.match(/^tweet_/) }
            #
            # if users_ids.include?(t['user_tweeter_id'])
            #   p "Duplicates user tweets array for #{t['user_tweeter_id']} #{o.id}"
            #   old_user = tweets.select{|m| m['user_tweeter_id'] == t['user_tweeter_id']}.first
            #   if old_user
            #     t['tweets'].map do |t2|
            #       if old_user['tweets'].select {|m| m['tweet_id'].to_i.to_s == t2['tweet_id'].to_i.to_s }.empty?
            #         t2['tweet_id'] = t2['tweet_id'].to_i.to_s
            #         old_user['tweets'] << t2
            #       end
            #     end
            #     changed = true
            #   else
            #     p "Can find old user array for #{t['user_tweeter_id']} #{o.id}"
            #   end
            # else
            #   users_ids << t['user_tweeter_id']
            #   tweets << t
            # end


            # if !t['tweets'] && !t.select{|m| m.match(/^tweet_/)}.empty?
            #   t['tweets'] = []
            #   t['tweets'] << t.select{|m| m.match(/^tweet_/)}
            #   changed = true
            # end

            # t.delete_if{|m| m.match(/^tweet_/) }

            # t['tweets'].map do |t2|
            #   if tweets_ids.include?(t2['tweet_id'])
            #     p "duplicates tweet for #{t2['tweet_id']} #{o.id}"
            #   else
            #     tweets_ids << t2['tweet_id']
            #   end
            # end

            # t['tweets'].map do |t2|
            #   if t2['tweet_date'].is_a?(Hash)
            #     t2['tweet_date'] = t2['tweet_date']['iso']
            #     changed = true
            #     p "Hash for #{o.id}"
            #   end
            # end
            changed = true
            #
            unless t['last_tweet_date']
              p "Empty last date for #{o.id}"

            end

            t['last_tweet_date'] = t['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
          end
        end

        if changed
          objects << { update_one: { filter: { _id: o.id }, update: { '$set' => {
              tweets: o['tweets'],
              tl_count: o['tweets'].count,
              tweets_count: o['tweets'].map{ |m| m['tweets'].count }.sum,
              stats_all: o['tweets'].count
          }}}}
        end
      rescue Exception => e
        p "#{class_name}##{o.id}"
        p e.message
        pp e.backtrace
      end
    end

    if objects.count > 0
      Rails.logger.info "Update bulk #{objects.count} objects for class #{class_name}"
      ret = class_name.constantize.collection.bulk_write(objects)
      Rails.logger.info ret
    end
  end

  def add_tweet_to_db(article_id, tweet_id)
    obj = nil
    article = Parse::Pointer.new({'className' => 'Article', 'objectId' => article_id})
    Retriable.retriable do
      obj = Parse::Query.new('Tweet').tap do |q|
        q.eq('article', article)
        q.eq('tweet_id', tweet_id)
      end.get.first
    end

    unless obj
      Retriable.retriable do
        Parse::Object.new('Tweet', {
            article: article,
            tweet_id: tweet_id
        }).save
      end
    end
  end
end
