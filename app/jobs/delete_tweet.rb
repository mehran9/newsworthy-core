class DeleteTweet < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger         # Logger for debug / info message

  # NO MORE USABLE
  def perform(tweet_id)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start DeleteTweet #{tweet_id} at #{start_time.strftime('%H:%M:%S')}..."

    tweet = nil
    Retriable.retriable do
      tweet = Parse::Query.new('Tweet').eq('tweet_id', tweet_id).get.first
    end

    @logger.info "Tweet #{tweet_id} not found in database" and return unless tweet

    article = nil
    Retriable.retriable do
      article = Parse::Query.new('Article').eq('objectId', tweet['article'].id).get.first
    end

    return ApplicationController.error(@logger, "Can't find Article##{tweet['article'].id}") unless article

    deleted_tweet = article['tweets'].select{|t| t['tweet_id'].to_s == tweet['tweet_id']}.first
    if deleted_tweet
      article['tweets'].delete(deleted_tweet)
      article['tweets_count'] = article['tweets'].count

      if article['tweets_count'] > 0
        @logger.info "Saving article #{article.id}..."
        Retriable.retriable do
          article.save
        end

        update_related(article)

        @logger.info "Deleting old tweet #{tweet_id} from in database..."
        Retriable.retriable do
          tweet.parse_delete
        end
      else
        @logger.info "Deleting article #{article.id} from in database..."
        Article.where(id: article.id).destroy_all
      end
    else
      ApplicationController.error(@logger, "Can't delete tweet #{tweet['tweet_id']} in Article##{article.id}")
    end

    @logger.info "DeleteTweet finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def update_related(article)
    %w(NetworkTweets IndustryTweets).map do |class_name|
      obj = nil
      Retriable.retriable do
        obj = Parse::Query.new(class_name).tap do |q|
          q.eq('Article', article.pointer)
        end.get
      end

      unless obj.empty?
        obj.map do |o|
          @logger.info "Updating #{class_name}##{o.id}..."
          o['tweets'] = article['tweets']
          o['tweets_count'] = article['tweets_count']
          Retriable.retriable do
            o.save
          end
        end
      end
    end
  end
end
