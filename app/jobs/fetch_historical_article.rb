class FetchHistoricalArticle < ActiveJob::Base
  queue_as :default

  attr_accessor :logger
  attr_accessor :tweet
  attr_accessor :topic

  def perform(tweet, topic)
    @logger = Delayed::Worker.logger
    @tweet = tweet
    @topic = topic

    start_time = Time.now
    @logger.info "Start fetching historical article for tweet #{tweet[:id]} at #{start_time.strftime('%H:%M:%S')}..."

    user = MentionedPerson.where(twitter_id: tweet[:user_id]).first

    return unless user

    tweet[:urls].each do |url|
      fetch_article(user, url)
    end

    @logger.info "Fetching historical article for tweet #{tweet[:id]} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}"
  end

  private

  def fetch_article(user, expanded_url)
    @logger.info "Fetch expanded url: #{expanded_url}"
    historical_article = HistoricalArticle.or({tweets_urls: expanded_url}, {url: expanded_url}).first

    fetch = Fetching::Content.new({
                                      logger: @logger,
                                      topic: @topic,
                                      tweet_id: @tweet[:id],
                                      diffbot_issue: true # Force no retries
                                  })

    if historical_article
      url = historical_article.url
      @logger.info "Find article #{url} using expanded url"
    else
      url = fetch.get_url(expanded_url)

      return unless url
    end

    @logger.info "Get historical content for url: #{url}"

    begin
      historical_article = HistoricalArticle.where(url: url).first

      if historical_article
        @logger.info "Find existing article for #{url} using id #{historical_article.id}"
      else
        article = Article.where(url: url).first
        if article
          @logger.info "Clone existing article for #{url} using id #{article.id}"
          historical_article = clone_article(article)
        else
          data = fetch.get_content(url, true)

          if data && !data.empty?
            if data.class == Article # found a duplicate article using md5 content
              @logger.info "Find existing Parse::Object article for #{url} using id #{article.id} and md5 content"
              historical_article = clone_article(data)
            else
              data.merge!({
                              'topic' => @topic, 'tweets' => [], 'score' => 1, 'tweets_urls' => [],
                              'stats_1h' => 0, 'stats_2h' => 1, 'stats_4h' => 1,
                              'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                              'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                              'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1
                          })
              data.delete('icon')
              historical_article = HistoricalArticle.create(data)
            end
          else
            @logger.info 'No content for the article, skiping'
            return
          end
        end
      end

      obj = historical_article.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == @tweet[:user_id].to_i.to_s }.first
      unless obj
        historical_article.push(tweets: {
            'tweets' => [],
            user_name: @tweet[:user_screen_name],
            user_tweeter_id: @tweet[:user_id].to_i.to_s,
            user_display_name: @tweet[:user_display_name],
            user_avatar: @tweet[:user_avatar],
            user_id: {
                '__type':    'Pointer',
                'className': 'MentionedPerson',
                'objectId':   user.id
            }
        })
        obj = historical_article.tweets.last
      end

      if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == @tweet[:id].to_i.to_s }.empty?
        obj['tweets'] << {
            tweet_id: @tweet[:id],
            tweet_content: @tweet[:text],
            tweet_date: @tweet[:date]
        }
      end

      obj['last_tweet_date'] = @tweet[:date]

      historical_article['tweets_count'] = historical_article['tweets'].map{ |m| m['tweets'].count }.sum
      historical_article['tl_count'] = historical_article['tweets'].count
      historical_article['stats_all'] = historical_article['tl_count']
      historical_article['stats_1h'] = historical_article['stats_1h'] + 1

      historical_article['tweets_urls'] = [] unless historical_article['tweets_urls']
      historical_article.push(tweets_urls: expanded_url) unless rl == expanded_url && historical_article.tweets_urls.include?(expanded_url)

      historical_article.save

      historical_article.array_add_relation('MentionedPerson', user.pointer)

      Utils.search_and_merge(historical_article)

      @logger.info "Article \"#{historical_article['title']}\" saved into #{historical_article.id}"
    rescue Exception => e
      ApplicationController.error(@logger, "Can't save historical article #{url} tweet_id: #{@tweet[:id]}", e)
    end
  end

  def clone_article(article)
    excludes = %w(_id _created_at _updated_at)
    new_article = HistoricalArticle.create(article.attributes.select {|s| !excludes.include?(s) })
    ArticleThoughtLeader.where(owningId: article.id).all.each do |t|
      HistoricalArticleThoughtLeader.where(owningId: new_article.id, relatedId: t.relatedId).find_or_create_by
    end
    new_article
  end
end
