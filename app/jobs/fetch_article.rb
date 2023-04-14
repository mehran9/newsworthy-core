# noinspection RubyStringKeysInHashInspection

class FetchArticle < ActiveJob::Base
  queue_as :default
  # TODO: Wait until activejob release priority option
  # queue_with_priority -10

  attr_accessor :diffbot_cache
  attr_accessor :retries
  attr_accessor :diffbot_issue
  attr_accessor :logger
  attr_accessor :tweet
  attr_accessor :topic

  def perform(tweet, topic, url = nil, retries = 0, diffbot_issue = false)
    @logger = Delayed::Worker.logger
    @tweet = tweet
    @topic = topic
    @retries = retries
    @diffbot_issue = diffbot_issue
    @diffbot_cache = nil

    @logger.info "Start fetching #{tweet[:id]}"

    user = save_user

    return unless user

    if url
      fetch_article(user, url)
    else
      tweet[:urls].each do |u|
        fetch_article(user, u) if u
      end
    end
  end

  private

  def save_user
    streamer = Streamer.where(topic: @topic.parameterize).first

    begin
      user = ThoughtLeader.where(twitter_id: @tweet[:user_id]).first

      unless user
        user = ThoughtLeader.create({
            twitter_id: @tweet[:user_id],
            name: @tweet[:user_screen_name],
            display_name: @tweet[:user_display_name],
            avatar: @tweet[:user_avatar],
            summary: @tweet[:user_description],
            country: @tweet[:user_country],
            language: @tweet[:user_language],
            followers_count: @tweet[:user_followers_count],
            mentions: [],
            mentions_count: 0,
            score: 1,
            average_mention_score: 0,
            average_article_score: 0,
            average_network_score: 0,
            identified_by_mention: false,
            Hidden: false,
            disabled: false,
            profile_updated_at: Time.now,
            streamer: (streamer ? streamer.pointer : nil)
        })

        # If it's a new ThoughtLeaders, add it to Search Class
        add_object_to_search(user)

        # Add a job in cue to get information about the thought leader
        # TODO: perform_later and get update_article_networks
        GetUserInformation.perform_now(user.id.to_s, 'ThoughtLeader',
          {
            name: user['display_name'],
            twitter: user['name']
          }
        )
      end
      user
    rescue Exception => e
      return ApplicationController.error(@logger, "Can't save user", e)
    end
  end

  def fetch_article(user, expanded_url)
    @logger.info "Fetch expanded url: #{expanded_url}"
    article = Article.or({tweets_urls: expanded_url}, {url: expanded_url}).first

    new_article = false

    if article
      url = article.url
      @logger.info "Find article #{url} using expanded url"
      fetch = Fetching::Content.new({
                                        logger: @logger,
                                        topic: @topic,
                                        tweet: @tweet,
                                        retries: @retries,
                                        article: article,
                                        diffbot_issue: @diffbot_issue
                                    })
    else
      fetch = Fetching::Content.new({
                                        logger: @logger,
                                        topic: @topic,
                                        tweet: @tweet,
                                        retries: @retries,
                                        diffbot_issue: @diffbot_issue
                                    })
      url = fetch.get_url(expanded_url)

      return unless url

      article = Article.where(url: url).first
    end

    @logger.info "Get content for url: #{url}"

    begin
      data = fetch.get_content(url)

      if data and (data.class == Article || !data.empty?)
        if data.class == Article # found a duplicate article using md5 content
          article = data
        elsif !article
          data.merge!({
                          'topic' => @topic, 'tweets' => [], 'score' => 1, 'tweets_urls' => [],
                          'stats_1h' => 0, 'stats_2h' => 1, 'stats_4h' => 1,
                          'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                          'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                          'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1
                      })
          article = Article.new(data)
          new_article = true
        else
          article.save(data)
        end
      elsif !article
        @logger.info 'No content for the article, skiping'
        return
      end

      # Flag if we add a new user to the article
      new_user = add_tweets(user, article)

      # Update tweets_count
      article['tweets_count'] = article.tweets.map{ |m| m['tweets'].count }.sum
      article['tl_count'] = article.tweets.count
      article['stats_all'] = article['tl_count']
      article['stats_1h'] = article['stats_1h'] + 1

      article['tweets_urls'] = [] unless article['tweets_urls']
      article.push(tweets_urls: expanded_url) unless url == expanded_url && article.tweets_urls.include?(expanded_url)

      # We set website icon with Diffbot before, it's time to remove it from the data (we don't want icons for Article)
      icon = article['icon']
      article.unset('icon')

      article.save

      # Add networks and ThoughtLeaders if we added a new tweet to the article
      if new_user
        # Add this user in ThoughtLeaders' article
        article.array_add_relation('ThoughtLeaders', user.pointer)

        # Add all user's networks & industries to Article
        add_related(user, article)
      end

      #TODO: Sometimes an article get saved and just after deleted by GetPublisher.. Potential issue here

      # If it's a new article, fetch information about the Publisher
      if new_article
        @logger.info "Get Publisher information for #{article['site_name']} (#{article['publication_name']} #{@tweet[:id]})"
        GetPublisher.perform_later(
            article['site_name'],
            article['publication_name'],
            icon,
            article.id,
            @tweet[:id]
        )
      else
        update_mentions(user, article) if article['mentions'] && article['mentions'].is_a?(Array) && !article['mentions'].empty?

        publisher = Publisher.where(publication_name: article['publication_name']).first

        if publisher
          Utils.update_article_score(article.id, publisher['rank'])
          UpdateScores.perform_later(user.id, 'ThoughtLeader')
        end
      end

      Utils.search_and_merge(article)

      @logger.info "Article \"#{article['title']}\" saved into #{article.id}"
    rescue Exception => e
      ApplicationController.error(@logger, "Can't save article #{url} (id: #{(article ? article['id']: '')})", e)
    end
  end

  def add_tweets(tl, article)
    obj = article.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == tl['twitter_id'].to_i.to_s }.first
    new_user = false

    unless obj
      article.push(tweets: {
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
      obj = article.tweets.last
      new_user = true
    end

    if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == @tweet[:tweet_id] }.empty?
      obj['tweets'] << {
        'tweet_id' => @tweet[:id],
        'tweet_content' => @tweet[:text],
        'tweet_date' => @tweet[:date]
      }
    end

    obj['last_tweet_date'] = obj['tweets'].sort_by { |t| t['tweet_date'] }.last['tweet_date']
    new_user
  end

  def add_related(tl, article)
    %w(Network Industry).each do |class_name|
      @logger.info "Add #{class_name} to Article..."

      ids = "ThoughtLeader#{class_name}".constantize.where(owningId: tl.id).pluck(:relatedId)

      if ids && !ids.empty?
        class_name.constantize.in(id: ids).map do |n|
          begin
            article.array_add_relation(class_name.pluralize, n.pointer) # eg: From Network to Networks association

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

            add_tweets(tl, obj)

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
    @logger.info "Add ThoughtLeaders \"#{obj['display_name']}\" to Search Class"

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

  def update_mentions(user, article)
    article['mentions'].map do |m|
      id = m['id'] || m['objectId']
      @logger.info "Update mention #{id}..."

      mention = Mention.where(id: id).first

      if mention
        obj = mention.tweets.select{|o| o['user_tweeter_id'].to_i.to_s == @tweet[:user_id].to_i.to_s }.first
        unless obj
          mention.push(tweets: {
              'tweets' => [],
              user_name: @tweet[:user_screen_name],
              user_tweeter_id: @tweet[:user_id].to_i.to_s,
              user_display_name: @tweet[:user_display_name],
              user_avatar: @tweet[:user_avatar],
              user_id: {
                  '__type':    'Pointer',
                  'className': 'ThoughtLeaders',
                  'objectId':   user.id
              }
          })
          obj = mention['tweets'].last
        end

        if obj['tweets'].select {|t| t['tweet_id'].to_i.to_s == @tweet[:id].to_i.to_s }.empty?
          obj['tweets'] << {
              tweet_id: @tweet[:id],
              tweet_content: @tweet[:text],
              tweet_date: @tweet[:date]
          }
        end

        obj['last_tweet_date'] = @tweet[:date]

        # Update tweets_count
        mention['tweets_count'] = mention['tweets'].map{ |o| o['tweets'].count }.sum
        mention['tl_count'] = mention['tweets'].count
        mention['stats_all'] = mention['tl_count']
        mention['stats_1h'] = mention['stats_1h'] + 1

        mention.save
      end
    end
  end
end
