class FetchTweets < ActiveJob::Base
  queue_as :low_priority

  def perform(object_id, force = false)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start FetchTweets for MentionedPerson##{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    mp = MentionedPerson.where(id: object_id).first

    unless mp
      ApplicationController.error(@logger, "FetchTweets MentionedPerson##{object_id} not found. Exiting")
      return
    end

    return @logger.warn "Tweets already fetched for MentionedPerson##{object_id}. Exiting" if !force && mp['tweets_fetched']

    proxy = "http://#{Settings.proxies.sample}"
    client = Utils.twitter_client(nil, proxy)

    @logger.info "Get historical tweets for MentionedPerson##{object_id} with proxy #{proxy}..."

    last_tweet_id = nil
    16.times do #3,200 max historical tweets
      begin
        count = 0
        opts = { user_id: mp['twitter_id'], count: 200 }
        opts[:max_id] = last_tweet_id if last_tweet_id
        @logger.info "Fetch tweets from #{opts}"
        client.user_timeline(opts).each do |tweet|
          if tweet.urls? && (Rails.env.development? || tweet.lang == Settings.tweet_expected_lang || !tweet.lang)
            @logger.info "Fetch historical tweet #{tweet.id}"
            FetchHistoricalArticle.perform_later(Utils.tweet_to_h(tweet), 'Venture Capital')
          end
          count += 1
          last_tweet_id = tweet.id
        end
        break if count < 200 || count == 0
      rescue Exception => e
        ApplicationController.error(@logger, "Can't fetch historical tweets for MentionedPerson##{object_id}", e)
      end
    end

    mp.update_attribute(:tweets_fetched, true)

    @logger.info "FetchTweets for MentionedPerson##{object_id} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
