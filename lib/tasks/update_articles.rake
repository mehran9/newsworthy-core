# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_articles do
  task 'less_2_days' => :environment do
    # Update all articles created less than 2 days

    start_time = Time.now
    Rails.logger.info "-> Start updating articles less_2_days at #{start_time.strftime('%H:%M:%S')}..."

    count = Article.only(:url).where(:_created_at.gte => 2.days.ago).map do |a|
      UpdateArticle.perform_later(a.id, a['url'])
    end.count

    Rails.logger.info "-> Updated less_2_days for #{count} Article in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task '2_to_14_days' => :environment do
    # Update all articles created more than 2 days and less than 14 days

    start_time = Time.now
    Rails.logger.info "-> Start updating articles 2_to_14_days at #{start_time.strftime('%H:%M:%S')}..."

    count = Article.only(:url).where(:_created_at.lt => 2.days.ago, :_created_at.gte => 14.days.ago).map do |a|
      UpdateArticle.perform_later(a.id, a['url'])
    end.count

    Rails.logger.info "-> Updated 2_to_14_days for #{count} Article in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :categories => :environment do
    # Old task to update all articles
    start_time = Time.now
    Rails.logger.info "Start updating articles at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Article').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_articles:categories] Can't fetch article", e)
    end

    Rails.logger.info 'No articles to update. Exiting...' and next if !count || count['count'] == 0

    limit = (Rails.env.development? ? 10 : 1000)
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} articles with max #{limit} per page, so looping for #{pages + 1} pages"

    Parallel.each(0..pages, in_threads: 2) do |i|
      begin
        Rails.logger.info "Get articles from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Article').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          ret.each do |a|
            ChangeArticleCategories.perform_later(a['objectId'])
          end
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_articles:cron] Can't get articles", e)
      end
    end
  end

  task :change_cat => :environment do
    @logger = Delayed::Worker.logger
    start_time = Time.now
    object_id = 'slLSCivMMe'
    @logger.info "Start updating article #{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    begin
      article = nil
      Retriable.retriable do
        article = Parse::Query.new('Article').eq('objectId', object_id).get.first
      end
      @logger.info "Can't find article #{object_id}. Exiting" and return unless article

      categories = []
      sub_categories = []

      article['category_ids'].each do |c|
        cat = Settings.categories[c[0..1].to_sym]
        sub_cat = Settings.categories[c[0..4].to_sym]
        categories << cat if cat && !categories.include?(cat)
        sub_categories << sub_cat if sub_cat && !categories.include?(sub_cat)
      end

      article['Categories'] = categories
      article['SubCategories'] = sub_categories

      Retriable.retriable do
        article.save
      end

      @logger.info "Article #{object_id} updated in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
    rescue Exception => e
      # unless e.message == '116: The object is too large -- should be less than 128 kB.'
      ApplicationController.error(@logger, "Can't update article #{object_id}", e)
      # end
    end
  end

  task :delete_banned  => :environment do
    start_time = Time.now
    Rails.logger.info "Start deleting Articles at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('BannedPublication').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_articles:delete_banned] Can't get Parse count", e)
    end

    Rails.logger.info 'No BannedPublication. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} BannedPublication with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('BannedPublication').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_articles:delete_banned] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} BannedPublication (#{count['count']} expected)"

    Rails.logger.info 'Loop through all BannedPublication...'

    total = 0
    Parallel.each_with_index(publishers, in_threads: 2) do |p,i|
      count = nil
      prefix = "#{i}/#{publishers.count} >"
      begin
        Retriable.retriable do
          count = Parse::Query.new('Article').tap do |q|
            q.eq('publication_name', p['name'])
          end.get.count
        end

        Rails.logger.info "#{prefix} Found #{count} Articles with banned publication: #{p['name']}" if count > 0
        total += count if count.is_a?(Fixnum)
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_articles:delete_banned] #{prefix} Can't fetch Article: #{p['name']}", e)
      end
    end

    Rails.logger.info "Found #{total} Articles banned in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_tweets => :environment do
    # Update tweets avatar url

    start_time = Time.now
    main_class = 'Article'
    Rails.logger.info "-> Start updating #{main_class} stats at #{start_time.strftime('%H:%M:%S')}..."

    objects = []
    avatars = {}
    created_at = 99.years.ago
    run = true
    elem = 0

    while run do
      begin
        Rails.logger.info "   Get the ##{elem} #{main_class}. Created at: #{created_at}"
        ret = nil
        Retriable.retriable do
          ret = Parse::Query.new(main_class).tap do |q|
            q.limit = 1000
            q.skip = 0
            q.order_by = 'createdAt'
            q.greater_than('createdAt', Parse::Date.new(created_at))
          end.get
        end

        if ret.empty? || ret.count <= 0
          Rails.logger.info "   Find limits for #{main_class}: #{ret.count}. Break loop..."
          run = false
        else
          ret.each do |a|
            elem += 1
            update = false

            next unless a['tweets'] && a['tweets'].is_a?(Array)

            a['tweets'].map do |t|
              next if t['user_avatar']

              avatar = 'https://abs.twimg.com/sticky/default_profile_images/default_profile_6_normal.png'

              if t['user_tweeter_id']
                if avatars.has_key?(t['user_tweeter_id'])
                  avatar = avatars[t['user_tweeter_id']]
                else
                  user = nil
                  Retriable.retriable do
                    user = Parse::Query.new('ThoughtLeaders').tap do |q|
                      q.eq('twitter_id', t['user_tweeter_id'].to_s)
                    end.get.first
                  end

                  if user && user['avatar']
                    avatar = user['avatar']
                    avatars[t['user_tweeter_id']] = avatar
                  else
                    Rails.logger.info '   No user found in db...'
                  end
                end
              end

              unless t['user_avatar'] == avatar
                t['user_avatar'] = avatar
                update = true
              end
            end

            objects << a if update

            if objects.count == 50
              Rails.logger.info '   Updating 50 objects...'
              batch = Parse::Batch.new
              objects.each {|o| batch.update_object(o) }
              Retriable.retriable do
                batch.run!
              end

              objects = []
            end
          end
          created_at = ret.last['createdAt']
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_stats:all] Can't fetch #{main_class}", e)
      end
    end

    if objects.count > 0
      Rails.logger.info "   Updating last #{objects.count} objects..."
      batch = Parse::Batch.new
      objects.each {|o| batch.update_object(o) }
      Retriable.retriable do
        batch.run!
      end
    end

    Rails.logger.info "-> Updated stats for #{objects.count} #{main_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_mentions => :environment do
    # Update tweets avatar url

    start_time = Time.now
    main_class = 'Article'
    Rails.logger.info "-> Start updating #{main_class} mentions at #{start_time.strftime('%H:%M:%S')}..."

    created_at = 99.years.ago
    run = true
    elem = 0

    while run do
      begin
        Rails.logger.info "   Get the ##{elem} #{main_class}. Created at: #{created_at}"
        ret = nil
        Retriable.retriable do
          ret = Parse::Query.new(main_class).tap do |q|
            q.limit = 1000
            q.skip = 0
            q.order_by = 'createdAt'
            q.greater_than('createdAt', Parse::Date.new(created_at))
            q.less_than('createdAt', Parse::Date.new('2016-03-31T13:35:00.000Z'))
            q.not_eq('mentions_fetched', true)
          end.get
        end

        if ret.empty? || ret.count <= 0
          Rails.logger.info "   Find limits for #{main_class}: #{ret.count}. Break loop..."
          run = false
        else
          ret.each do |a|
            elem += 1
            AddEntities.perform_later(a['objectId'])
          end
          created_at = ret.last['createdAt']
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_stats:all] Can't fetch #{main_class}", e)
      end
    end

    Rails.logger.info "-> Updated mentions for #{objects.count} #{main_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :check_tl => :environment do
    start_time = Time.now
    tl_ids = []
    tweeters_ids = []

    # models = %w(Article IndustryTweet NetworkTweet Mention MentionIndustryTweet MentionNetworkTweet)
    models = %w(Article)

    models.map do |main_class|
      Rails.logger.info "-> Start #{main_class} Orphans check at #{start_time.strftime('%H:%M:%S')}..."

      not_found = []
      not_found_tweet = []

      deleted = []
      objects = []

      main_class.constantize.only(:tweets).all.map do |o|
        changed = false

        o['tweets'].each_with_index do |t, i|
          begin
            user_id = nil
            if t['user_id']
              user_id = t['user_id']['objectId']

              next if tl_ids.include?(user_id)

              if not_found.include?(user_id)
                if o['tweets'].count == 1
                  # p "TL re not found #{user_id} #{t['user_tweeter_id']} in #{o.id} delete"
                  deleted << o.id
                else
                  # p "TL re not found #{user_id} #{t['user_tweeter_id']} in #{o.id}"
                  o['tweets'].delete_at(i)
                  changed = true
                end

                next
              end

              if ThoughtLeader.where(id: user_id).first
                tl_ids << user_id.to_s
                next
              end
            end

            tl = ThoughtLeader.where(twitter_id: t['user_tweeter_id'].to_s).first

            if tl
              tl_ids << tl.id.to_s

              if t['user_id']
                t['user_id']['objectId'] = tl.id.to_s
                t['user_id']['className'] = 'ThoughtLeaders'
                changed = true
              end
            else
              if o['tweets'].count == 1
                # p "TL re not found #{user_id} #{t['user_tweeter_id']} in #{o.id} delete"
                deleted << o.id
              else
                # p "TL re not found #{user_id} #{t['user_tweeter_id']} in #{o.id}"
                o['tweets'].delete_at(i)
                changed = true
              end

              if user_id
                not_found << user_id.to_s
              end

              not_found_tweet << t['user_tweeter_id'].to_s
            end
          rescue Exception => e
            p "#{main_class}##{o.id}"
            p e.message
            pp e.backtrace
          end
        end

        if changed
          objects << { update_one: { filter: { _id: o.id }, update: { '$set' => { tweets: o['tweets'] }}}}
        end
      end

      p "Found #{objects.count} #{main_class} to change and #{deleted.count} to delete"
      p "Found #{not_found.count} TL not found"
      p "Found #{not_found_tweet.count} TL ids not found"

      if objects.count > 0
        Rails.logger.info "Update bulk #{objects.count} objects for class #{class_name}"
        ret = class_name.constantize.collection.bulk_write(objects)
        Rails.logger.info ret
      end

      if deleted.count > 0
        deleted.map do |o|
          a = Article.where(id: o).first
          if a
            p "Delete article #{o}"
            a.destroy
          end
        end
      end

      if not_found.count > 0
        not_found.map do |o|
          %w(ThoughtLeaderIndustry ThoughtLeaderNetwork).map do |object_class|
            ret = object_class.constantize.where(owningId: o).destroy_all
            p "Delete #{object_class} #{ret}"
          end

          %w(ArticleThoughtLeader ArticleTlMention).map do |object_class|
            ret = object_class.constantize.where(relatedId: o).destroy_all
            p "Delete #{object_class} #{ret}"
          end

          ret = Search.where(EntityId: o, EntityType: 'ThoughtLeaders').destroy_all
          p "Delete Search #{ret}"
        end
      end
      Rails.logger.info "-> Found Orphans for #{main_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
    end
  end

  task :add_missing_mentions => :environment do
    start_time = Time.now
    Rails.logger.info "-> Start add_missing_mentions at #{start_time.strftime('%H:%M:%S')}..."

    count = 0
    Article.where(:_created_at.gte => 6.days.ago).map do |a|
      unless a['mentions_fetched']
        pub = Publisher.where(publication_name: a['publication_name']).first
        if pub && pub['rank'] <= 5000
          tweet_id = a['tweets'].last['tweets'].last['tweet_id']
          p "Fetch mentions for #{tweet_id} #{a['title']}"
          AddEntities.perform_later(a.id, tweet_id, true, pub['rank'])
          count += 1
        end
      end
    end

    Rails.logger.info "-> Task add_missing_mentions finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  def twitter_client
    @twitter_client ||= Twitter::REST::Client.new do |config|
      config.consumer_key        = Settings.twitter.consumer_key
      config.consumer_secret     = Settings.twitter.consumer_secret
      config.access_token        = Settings.twitter.oauth_token
      config.access_token_secret = Settings.twitter.oauth_token_secret
    end
  end
end
