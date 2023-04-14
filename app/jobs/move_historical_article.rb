class MoveHistoricalArticle < ActiveJob::Base
  queue_as :default

  attr_accessor :logger

  def perform(twitter_id, force = false)
    @logger = Delayed::Worker.logger

    start_time = Time.now
    @logger.info "Start moving historical articles for MentionPerson #{twitter_id} at #{start_time.strftime('%H:%M:%S')}..."

    mp = MentionedPerson.where(twitter_id: twitter_id).first

    return @logger.warn "Can't find MP id #{twitter_id}" unless mp

    return @logger.warn "Historical articles already moved for #{mp.id}. Exiting" if !force && mp['articles_moved']

    tl = ThoughtLeader.where(twitter_id: twitter_id).first

    if tl
      return ApplicationController.error(@logger, "MentionPerson #{twitter_id} already exists in TL table") unless force
    else
      @logger.info "Migrate #{mp['name']} to TL"

      tl = move_mp(mp)

      @logger.info "Add ThoughtLeaders \"#{tl['display_name']}\" to Search Class"
      add_object_to_search(tl)
    end

    @logger.info "Migrate #{mp['name']}'s Historical Articles to Articles"

    HistoricalArticleMentionedPerson.where(relatedId: mp.id).each do |m|
      old_article = HistoricalArticle.where(id: m.owningId).first
      next unless old_article

      @logger.info "Migrating '#{old_article['title']}'..."
      move_article(tl, old_article)
    end

    mp.update_attribute(:articles_moved, true)

    @logger.info "Moving historical articles for MentionPerson #{twitter_id} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}"
  end

  private

  def move_mp(mp)
    excludes = %w(_id _created_at _updated_at)
    tl = ThoughtLeader.new(mp.attributes.select {|s| !excludes.include?(s) })
    tl['Hidden'] = false
    tl.save

    MentionedPersonNetwork.where(owningId: mp.id).each do |o|
      ThoughtLeaderNetwork.where(owningId: tl.id, relatedId: o.relatedId).find_or_create_by
    end

    MentionedPersonIndustry.where(owningId: mp.id).each do |o|
      ThoughtLeaderIndustry.where(owningId: tl.id, relatedId: o.relatedId).find_or_create_by
    end

    tl
  end

  def move_article(tl, old_article)
    article = Article.where(url: old_article['url']).first

    old_article.tweets = old_article.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == tl['twitter_id'].to_i.to_s }

    old_article.tweets.first['user_id']['className'] = 'ThoughtLeaders'
    old_article.tweets.first['user_id']['objectId'] = tl.id

    if article
      add_tweets(tl, article, old_article.tweets)
    else
      excludes = %w(_id)
      article = Article.new(old_article.attributes.select {|s| !excludes.include?(s) })
    end

    article['tweets_count'] = article.tweets.map{ |m| m['tweets'].count }.sum
    article['tl_count'] = article.tweets.count
    article['stats_all'] = article['tl_count']

    article.save

    article.array_add_relation('ThoughtLeaders', tl.pointer)
    add_related(tl, article, old_article.tweets)
  end

  def add_tweets(tl, related_object, tweets)
    obj = related_object.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == tl['twitter_id'].to_i.to_s }.first

    unless obj
      related_object.push(tweets: {
          'tweets' => [],
          'user_name' => tl['name'],
          'user_tweeter_id' => tl['twitter_id'].to_i.to_s,
          'user_display_name' => tl['display_name'],
          'user_avatar' => tl['avatar'],
          'user_id' => {
              '__type':    'Pointer',
              'className': 'ThoughtLeaders',
              'objectId':   tl.id
          }
      })
      obj = related_object.tweets.last
    end

    tweets.first['tweets'].each do |tweet|
      if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == tweet['tweet_id'].to_i.to_s }.empty?
        obj['tweets'] << tweet
      end
    end

    obj['last_tweet_date'] = obj['tweets'].sort_by { |t| t['tweet_date'] }.last['tweet_date']
  end

  def add_related(tl, article, tweets)
    %w(Network Industry).each do |class_name|
      @logger.info "Add #{class_name} to Article..."

      ids = "ThoughtLeader#{class_name}".constantize.where(owningId: tl.id).pluck(:relatedId)

      if ids && !ids.empty?
        class_name.constantize.in(id: ids).map do |n|
          begin
            article.array_add_relation(class_name.pluralize, n.pointer)

            obj = "#{class_name}Tweet".constantize.where("_p_#{class_name}": "#{class_name}$#{n.id}", _p_Article: "Article$#{article.id}").first

            unless obj
              obj = "#{class_name}Tweet".constantize.create(
                  {
                      'tweets' => [],
                      class_name => n.pointer,
                      'Article' => article.pointer,
                      'stats_1h' => 0, 'stats_2h' => 1, 'stats_4h' => 1,
                      'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                      'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                      'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1
                  }
              )
            end

            add_tweets(tl, obj, tweets)

            obj['tweets_count'] = obj['tweets'].map{ |m| m['tweets'].count }.sum
            obj['tl_count'] = obj['tweets'].count
            obj['stats_all'] = obj['tl_count']

            obj.save
          rescue Exception => e
            ApplicationController.error(@logger, "Can't save #{class_name} #{obj.id} & article #{article.id}", e)
          end
        end
      end
    end
  end

  def add_object_to_search(obj)
    search = Search.where(EntityType: 'ThoughtLeaders', EntityName: obj['display_name']).first

    data = {
        EntityId: obj.id,
        EntityType: 'ThoughtLeaders',
        EntityName: obj['display_name'],
        EntityNameLC: obj['display_name'].downcase,
        EntityMedia: obj['avatar'],
        ThoughtLeaders: obj.pointer
    }

    if search
      search.update(data)
    else
      Search.create(data)
    end
  end
end
