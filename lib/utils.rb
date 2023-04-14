module Utils
  class << self
    def twitter_client(twitter = nil, proxy = nil)
      twitter = Settings.streamers.sample unless twitter

      Twitter::REST::Client.new do |config|
        config.consumer_key        = twitter['consumer_key']
        config.consumer_secret     = twitter['consumer_secret']
        config.access_token        = twitter['oauth_token']
        config.access_token_secret = twitter['oauth_token_secret']
        config.proxy               = proxy if proxy
      end
    end

    def get_twitter_avatar(user)
      if user.profile_image_url?
        user.profile_image_url_https.to_s.gsub('_normal', '_bigger')
      else
        nil
      end
    end

    def get_root_domain(url, logger = nil)
      @logger = get_logger(logger)

      begin
        if url =~ /:\/\//
          url = URI.parse(url.gsub(':////', '://')).host
        end
        PublicSuffix.parse(url).domain
      rescue Exception => e
        @logger.warn("Can't find get_root_domain: #{url} #{e.message}")
        # ApplicationController.error(@logger, "Can't find get_root_domain: #{url}", e)
      end
    end

    def order_images(images, number = 1.5)
      def ratio(a); (a.image.width.to_f / a.image.height.to_f); end
      images.sort_by{|a| (ratio(a) >= number ? ratio(a) - number : number - ratio(a)) }
    end

    def get_rank(publication_name, logger = nil)
      @logger = get_logger(logger)

      res = nil
      Retriable.retriable do
        res = Amazon::Awis.get_info(publication_name)
      end

      rank = nil
      rank_fetched = false
      rank_fetched_at = nil

      if res && res.success?
        if res.get_all('Country').count > 0
          rank = res.get_all('Country').select{|e| !e.rank.first.to_s.empty? }.sort_by{|e| e.rank.first.to_s.to_i }.first.rank.first.to_s.to_i
          @logger.info "Found rank for: #{publication_name} #{rank}"
        else
          @logger.info "No rank rank for: #{publication_name}"
        end
        rank_fetched = true
        rank_fetched_at = Time.now.utc.iso8601(3)
      else
        @logger.warn "No rank found for: #{publication_name}"
      end

      {rank: rank, rank_fetched: rank_fetched, rank_fetched_at: rank_fetched_at}
    end

    def update_article_score(article_id, rank)
      article = Article.where(id: article_id).first

      if article
        score = 1
        tls_ids = ArticleThoughtLeader.where(owningId: article_id).pluck(:relatedId)

        if tls_ids && !tls_ids.empty?
          rank = 2000000 unless rank
          sum = 0
          ThoughtLeader.in(id: tls_ids).pluck(:score).map do |t|
            sum += t if t
          end
          score = ((sum / tls_ids.count) / rank.to_f) * (article['stats_4h'] + 1)
        end

        article.update(score: score)
      end
    end

    def update_network_score(network)
      score = 1
      tls_ids = ThoughtLeaderNetwork.where(relatedId: network.id).pluck(:owningId)

      if tls_ids && !tls_ids.empty?
        sum = 0
        ThoughtLeader.in(id: tls_ids).pluck(:score).map do |t|
          sum += t if t
        end
        score = sum.to_f / tls_ids.count
      end

      Network.where(id: network.id).update(score: score)
    end

    def get_float(value, default = 0)
      if !value
        default
      elsif value.is_a?(Float) && value.nan?
        default
      else
        value
      end
    end

    def get_process_count(cmd)
      count = 0
      Dir['/proc/[0-9]*/cmdline'].each do|p|
        begin
          count += 1 if File.read(p).include?(cmd)
        rescue Exception => e
          # ignored
        end
      end
      count
    end

    def get_avg_score(obj, value = nil)
      stat = 0
      obj.map do |t|
        begin
          stat += t['score'] if !value || t['date'] >= value
        rescue
          0
        end
      end
      stat.to_f / obj.size
    end

    def add_tweet_to_array(tweets, t)
      obj = tweets.select{|m| m['user_tweeter_id'].to_i.to_s == t['user_tweeter_id'].to_i.to_s }.first
      unless obj
        tweets << t.select{|m| m.match(/^user_/)}.merge({'tweets' => []})
        obj = tweets.last
      end
      tweet = t.select{|m| m.match(/^tweet_/)}
      tweet['tweet_id'] = tweet['tweet_id'].to_i.to_s

      unless tweet['tweet_date']
        tweet['tweet_date'] = Time.now.utc.iso8601(3)
      end

      obj['tweets'] << tweet
      begin
        obj['last_tweet_date'] = obj['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
      rescue Exception => e
        obj['last_tweet_date'] = Time.now.utc.iso8601(3)
      end
      obj
    end

    def search_and_merge(article)
      if article.class.where(md5_content: article['md5_content']).count > 1
        MergeArticles.perform_later(article['md5_content'], nil, article.class.to_s)
      elsif article.class.where(url: article['url']).count > 1
        MergeArticles.perform_later(nil, article['url'], article.class.to_s)
      end
    end

    def tweet_to_h(tweet)
      {
          id: tweet.id.to_s,
          text: CGI.unescapeHTML(tweet.text),
          date: tweet.created_at.to_time.utc.iso8601(3),
          user_id: tweet.user.id.to_s,
          user_display_name: (tweet.user.name? ? tweet.user.name.gsub('(', '').gsub(')', '') : nil),
          user_avatar: Utils.get_twitter_avatar(tweet.user),
          user_screen_name: tweet.user.screen_name,
          user_description: (tweet.user.description? ? tweet.user.description : nil),
          user_country: (tweet.user.location? ? tweet.user.location : nil),
          user_language: (tweet.user.lang? ? tweet.user.lang : nil),
          user_followers_count: (tweet.user.followers_count ? tweet.user.followers_count : 0),
          urls: tweet.urls.map {|u| u.expanded_url.to_s}
      }
    end

    def extract_image_from_dbpedia(logger, url, page = nil)
      begin
        logger.info("Extract image using dbpedia link: #{url}")
        unless page
          page = MetaInspector.new(url, { faraday_options: { ssl: false }}).parsed
        end

        # https://en.wikipedia.org/w/api.php?action=parse&page=Microsoft&prop=text&format=json&section=0
        # https://en.wikipedia.org/w/api.php?action=query&titles=Swatch_Group&redirects=resolve&format=json&prop=redirects
        
        # Find the logo using dbpedia
        res = page.search("tr > td.property > a[text()='image']").first
        if res
          logo = res.parent.parent.search('ul > li:last-child span[property="dbp:image"]').first
          if logo
            logo = "http://commons.wikimedia.org/wiki/Special:FilePath/#{res.text}"
            logger.info("Find logo for #{url} using image: #{logo}")
            return logo
          end
        end

        %w(thumbnail depiction).each do |e|
          res = page.search("tr > td.property > a[text()='#{e}']").first
          if res
            logo = res.parent.parent.search('td:nth-child(2) > ul > li:last-child a').first['href'].gsub('?width=300','')
            if logo =~ /https?:\/\/[\S]+/
              logger.info("Find logo for #{url} using #{e}: #{logo}")
              return logo
            end
          end
        end
      rescue Exception => e
        return ApplicationController.error(logger, "Can't extract url from dbpedia: \"#{url}\"", e)
      end

      false
    end

    private

    def get_logger(logger)
      logger || Logger.new(STDOUT).tap{|l|
        l.level = "Logger::#{Rails.application.config.log_level.to_s.upcase}".constantize
      }
    end
  end
end
