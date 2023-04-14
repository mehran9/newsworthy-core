class MergeArticles < ActiveJob::Base
  queue_as :default

  attr_accessor :logger

  def perform(md5, url, class_name)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start merging articles #{md5} or #{url} at #{start_time.strftime('%H:%M:%S')}..."

    begin
      articles = class_name.constantize.or({md5_content: md5}, {url: url}).order(tweets_count: 'desc')

      return @logger.warn "Can't find articles with #{md5} or #{url}" if articles.empty?

      @logger.warn("Only one article with #{md5} or #{url}") and return if articles.count == 1

      article = articles.first
      article['url'] = articles.sort{|l, r| l['url'].size <=> r['url'].size}.first['url']
      articles.drop(1).map do |a|
        a['tweets'].map do |tweet|
          obj = article.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == tweet['user_tweeter_id'].to_i.to_s }.first
          if obj && obj['tweets'] && tweet['tweets']
            tweet['tweets'].map do |t|
              if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == t['tweet_id'].to_i.to_s }.empty?
                obj['tweets'] << t
              end
            end
          else
            article.push(tweets: tweet)
            obj = article.tweets.last
          end

          begin
            obj['last_tweet_date'] = obj['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
          rescue Exception => e
            obj['last_tweet_date'] = Time.now.utc.iso8601(3)
          end
        end

        if a['tweets_urls']
          if article['tweets_urls']
            a.tweets_urls.each do |u|
              article.push(tweets_urls: u) unless article.tweets_urls.include?(u)
            end
          else
            article['tweets_urls'] = a['tweets_urls']
          end
        end
      end
      begin
        article['tweets_count'] = article['tweets'].map{ |o| o['tweets'].count }.sum
      rescue Exception => e
        article['tweets_count'] = 1
      end
      article['tl_count'] = article['tweets'].count
      article['stats_all'] = article['tl_count']

      @logger.info "Save merged article #{article.id}..."
      article.save

      @logger.info 'Delete other articles...'
      class_name.constantize.in(id: articles.drop(1).map{|a| a.id }).destroy_all

      @logger.info "Merged #{articles.count} articles into #{article.id} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
    rescue Exception => e
      ApplicationController.error(@logger, "Can't merge article with md5 #{md5} or url #{url}", e)
    end
  end
end
