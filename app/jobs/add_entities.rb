# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class AddEntities < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger         # Logger for debug / info message
  attr_accessor :article        # Current Article
  attr_accessor :entities       # Meaningcloud Entities
  attr_accessor :sentiment      # Meaningcloud Sentiment
  attr_accessor :organizations  # Extracted Organizations
  attr_accessor :peoples        # Extracted Peoples
  attr_accessor :rank           # Publisher Rank
  attr_accessor :tweet          # Related tweet
  attr_accessor :tweet_content
  attr_accessor :mention_score  # Base for the mention score formula
  attr_accessor :mentions       # mentions to mentions, with mentions, on mentions

  # @param [ObjectId] object_id Parse Article id
  def perform(object_id, tweet_id, rank_set = false, rank = nil)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start AddEntities article #{object_id} #{tweet_id} at #{start_time.strftime('%H:%M:%S')}..."

    @rank = rank

    @article = Article.where(id: object_id.to_s).first

    return @logger.warn "Can't find Article##{object_id}" unless @article

    @tweet = @article['tweets'].select{|m| !m['tweets'].select{|t| t['tweet_id'].to_i.to_s == tweet_id.to_i.to_s }.empty? }.first

    unless @tweet
      return ApplicationController.error(@logger, "Can't find tweet #{tweet_id} for Article##{object_id}")
    end

    @tweet_content = @tweet['tweets'].select{|t| t['tweet_id'].to_i.to_s == tweet_id.to_i.to_s }.first.to_h

    unless @tweet_content
      return ApplicationController.error(@logger, "Can't find tweet_content #{tweet_id} for Article##{object_id}")
    end

    @entities = nil
    return unless get_meaningcloud_entities

    @organizations = []
    @peoples = []
    @events = []
    @products = []
    @mentions = []

    extract_entities

    if @peoples.empty? && @organizations.empty? && @events.empty? && @products.empty?
      @logger.warn "No entities found for Article##{object_id}" and return
    end

    get_current_publisher_rank unless rank_set

    @sentiment = []
    get_meaningcloud_sentiment

    extract_sentiment unless @sentiment.empty?

    # filter_sentiment

    calculate_mention_score

    Parallel.map(%w(peoples organizations events products), in_threads: (Rails.env.development? ? 1 : 2)) do |entity|
      send("add_#{entity}") unless instance_variable_get("@#{entity}").empty?
    end

    @logger.info 'Add mentions relationship...'
    add_mention_relations

    @logger.info "Save Article##{object_id}..."
    @article['mentions_fetched'] = true
    @article.save

    @logger.info "AddEntities finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def get_meaningcloud_entities
    @logger.info 'Fetch entities using MeaningCloud...'
    info = nil
    begin
      Retriable.retriable do
        info = MeaningCloud::Topics.extract(txt: @article['text'])
      end
    rescue Exception => e
      @logger.warn "Fail retry get_meaningcloud_entities MeaningCloud #{@article.id}: #{e.message}"
      return false
    end

    unless info && info['status']['msg'] == 'OK' && info['entity_list'] && info['entity_list'].count > 0
      unless info['status']['msg'] == 'OK'
        @logger.warn "No meaningcloud_entities data for #{@article.id} - Status: #{info['status']['msg']} Credit: #{info['status']['remaining_credits']}"
      end
      return false
    end

    @entities = info['entity_list']
    @logger.info "Found #{@entities.count} entities using MeaningCloud"
  end

  def extract_entities
    @logger.info 'Extract entities...'

    begin
      @entities.map do |c|
        if c['form'] && !c['form'].empty?
          data = { name: c['form'], relevance: c['relevance'] }

          unless c['semld_list'].blank?
            twitter = c['semld_list'].select{|s| s =~ /^@/ }.first
            data[:twitter] = twitter.gsub('@', '') if twitter

            data[:wikipedia_url] = c['semld_list'].select{|s| s.include?('en.wikipedia.org') }.first
          end

          if c['sementity']['type'] =~ /^Top>Person/ && @peoples.select {|o| o[:name] == c['form'] }.empty?
            @logger.info "Found a person: #{c['form']} with w: #{data[:wikipedia_url]} & t: #{data[:twitter]}"
            @peoples << data
          elsif c['sementity']['type'] =~ /^Top>Organization/ && @organizations.select {|o| o[:name] == c['form'] }.empty?
            @logger.info "Found an Organization: #{c['form']} with w: #{data[:wikipedia_url]}"
            @organizations << data
          elsif c['sementity']['type'] =~ /^Top>Event/ && @events.select {|o| o[:name] == c['form'] }.empty?
            @logger.info "Found an Event: #{c['form']} with w: #{data[:wikipedia_url]}"
            @events << data
          elsif c['sementity']['type'] =~ /^Top>Product/ && @products.select {|o| o[:name] == c['form'] }.empty?
            @logger.info "Found a Product: #{c['form']} with w: #{data[:wikipedia_url]}"
            @products << data
          end
        end
      end
    rescue Exception => e
      ApplicationController.error(@logger, 'Fail extracting entities', e)
    end
  end

  def get_meaningcloud_sentiment
    @logger.info 'Fetch sentiment using MeaningCloud...'
    info = nil
    begin
      Retriable.retriable do
        info = MeaningCloud::Sentiment.extract(txt: @article['text'])
      end
    rescue Exception => e
      @logger.warn "Fail retry get_meaningcloud_sentiment MeaningCloud #{@article.id}: #{e.message}"
      return false
    end

    unless info && info['status']['msg'] == 'OK' && info['sentimented_entity_list'] && info['sentimented_entity_list'].count > 0
      unless info['status']['msg'] == 'OK'
        @logger.warn "No meaningcloud_sentiment data for #{@article.id}: Status: #{info['status']['msg']} Credit: #{info['status']['remaining_credits']}"
      end
      return false
    end

    @sentiment = info['sentimented_entity_list']
    @logger.info "Found #{@sentiment.count} sentiment using MeaningCloud"
  end

  def extract_sentiment
    @logger.info 'Extract sentiment...'

    begin
      @sentiment.map do |c|
        if c['type'] =~ /^Top>Person/
          @logger.info "Found people sentiment for #{c['form']}: #{c['score_tag']}"
          @peoples.map{|p| p[:sentiment] = c['score_tag'] if p[:name] == c['form']}
        elsif c['type'] =~ /^Top>Organization/
          @logger.info "Found organization sentiment for #{c['form']}: #{c['score_tag']}"
          @organizations.map{|p| p[:sentiment] = c['score_tag'] if p[:name] == c['form']}
        elsif c['type'] =~ /^Top>Event/
          @logger.info "Found event sentiment for #{c['form']}: #{c['score_tag']}"
          @events.map{|p| p[:sentiment] = c['score_tag'] if p[:name] == c['form']}
        # elsif c['type'] =~ /^Top>Location/
        #   @logger.info "Found location sentiment for #{c['form']}: #{c['score_tag']}"
        #   @locations.map{|p| p[:sentiment] = c['score_tag'] if p[:name] == c['form']}
        elsif c['type'] =~ /^Top>Product/
          @logger.info "Found product sentiment for #{c['form']}: #{c['score_tag']}"
          @products.map{|p| p[:sentiment] = c['score_tag'] if p[:name] == c['form']}
        end
      end
    rescue Exception => e
      ApplicationController.error(@logger, 'Fail extracting sentiment', e)
    end
  end

  def add_peoples
    @logger.info 'Add peoples to database...'

    @peoples.map do |o|
      begin
        mp = nil
        user = nil
        new_obj = false

        if o[:twitter]
          @logger.info "Searching for MP #{o[:name]} (t: #{o[:twitter]})..."
          mp = MentionedPerson.where(name: o[:twitter]).first
        end

        unless mp
          @logger.info "Look up Twitter name: #{o[:name]}..."
          users = nil
          Retriable.retriable do
            users = Utils.twitter_client.user_search(o[:name])
          end

          unless users && users.count > 0
            @logger.info "Can't find a Twitter account for: #{o[:name]}"
            next
          end

          user = users.select{|u| u.name == o[:name]}.first

          unless user
            @logger.info "Can't find a good Twitter account for: #{o[:name]}"
            next
          end

          unless user.followers_count > 500 # || user.verified?
            @logger.info "Not enough followers: #{o[:name]} (#{user.followers_count})"
            next
          end

          o[:twitter] = user.screen_name

          @logger.info "Searching for MP #{o[:name]} (t: #{o[:twitter]})..."
          mp = MentionedPerson.where(twitter_id: user.id.to_s).first
        end

        unless mp
          @logger.info "Create new MP #{o[:name]} (t: #{o[:twitter]})..."
          mp = MentionedPerson.create(
              {
                  name: o[:twitter],
                  display_name: o[:name].gsub('(', '').gsub(')', ''),
                  twitter_id: user.id.to_s,
                  TwitterURL: "https://twitter.com/#{o[:twitter]}",
                  avatar: Utils.get_twitter_avatar(user),
                  summary: (user.description? ? user.description : nil),
                  country: (user.location? ? user.location : nil),
                  language: (user.lang? ? user.lang : nil),
                  followers_count: (user.followers_count ? user.followers_count : 0),
                  identified_by_mention: true,
                  score: 1,
                  average_mention_score: 0,
                  average_article_score: 0,
                  average_network_score: 0,
                  Hidden: true,
                  disabled: false,
                  mentions: [],
                  profile_updated_at: Time.now,
                  tweets_fetched: false
              }
          )
          new_obj = true
        end

        if check_article(mp['mentions'])
          mp.push(mentions: get_mentions_data(o))
        end

        mp['mentions_count'] = mp['mentions'].count
        mp['average_mention_score'] = calculate_ms(mp)
        mp['average_article_score'] = calculate_as(mp)
        mp['average_network_score'] = calculate_ns(mp)
        mp['score'] = calculate_score(mp)

        @logger.info "Saving MP #{o[:name]} with #{mp['mentions_count']} mentions count..."
        mp.save

        @article.array_add_relation('mp_mention', mp.pointer)

        if new_obj
          @logger.info "Fetch information for #{mp['display_name']}..."
          GetUserInformation.perform_now(mp.id.to_s, 'MentionedPerson',
                                         {
                                             name: mp['display_name'],
                                             twitter: mp['name']
                                         }, false
          )

          # FetchTweets.perform_later(mp.id.to_s)
        end

        add_mentions('people', o[:name], o[:sentiment], o[:wikipedia_url])
      rescue Exception => e
        ApplicationController.error(@logger, "Fail adding peoples #{o[:name]} (t: #{o[:twitter]})", e)
      end
    end
  end

  def add_organizations
    @logger.info 'Add organizations to database...'

    networks = []
    api = Dandelion::API.new(logger: @logger)

    @organizations.map do |o|
      response = api.fetch(o[:name], { relevance: o[:relevance], sentiment: o[:sentiment]})
      networks.concat(response) if response
    end

    return @logger.warn "No networks found (was #{@organizations.count})..." if networks.empty?

    networks.map do |o|
      begin
        network = Network.where(NetworkName: o[:NetworkName]).first
        new_obj = false

        unless network
          @logger.info "Create new Network #{o[:NetworkName]}..."

          network = Network.create(
              {
                  NetworkName: o[:NetworkName],
                  NetworkNameLC: o[:NetworkName].downcase,
                  identified_by_mention: true,
                  mentions: [],
                  mentions_count: 0,
                  score: 1,
                  Hidden: true
              }
          )
          new_obj = true
        end

        if check_article(network['mentions'])
          network.push(mentions: get_mentions_data(o))
        end
        network['mentions_count'] = network['mentions'].count

        @logger.info "Saving Network #{o[:NetworkName]} with #{network['mentions_count']} mentions count..."
        network.save

        @article.array_add_relation('network_mention', network.pointer)

        if new_obj
          GetNetworkInformation.perform_now(network.id.to_s, o[:NetworkUrl])
        end

        add_mentions('organization', o[:NetworkName], o[:sentiment], o[:wikipedia_url])
      rescue Exception => e
        ApplicationController.error(@logger, "Fail adding organizations #{o[:NetworkName]}", e)
      end
    end
  end

  def add_events
    @logger.info 'Add events to database...'

    @events.map do |o|
      add_mentions('event', o[:name], o[:sentiment], o[:wikipedia_url])
    end
  end

  def add_products
    @logger.info 'Add products to database...'

    @products.map do |o|
      add_mentions('product', o[:name], o[:sentiment], o[:wikipedia_url])
    end
  end

  def add_mentions(type, name, sentiment, wikipedia_url = nil)
    @logger.info "Add mention #{name} (#{type})..."

    begin
      mention = Mention.where(name: name, type: type).first

      unless mention
        @logger.info "Create new mention #{name} (#{type})..."
        mention = Mention.create({
            name: name,
            type: type,
            tweets: [],
            tweets_count: 1,
            tl_count: 1,
            image: nil,
            image_fetched: false,
            mention_score: [],
            average_mention_score: 0,
            sentiment_score: [],
            RelatedMentionsEmbedded: [],
            wikipedia_url: nil,
            'stats_1h' => 1, 'stats_2h' => 1, 'stats_4h' => 1,
            'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
            'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
            'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1,
            'sentiment_score_1h' => 0, 'sentiment_score_2h' => 0, 'sentiment_score_4h' => 0,
            'sentiment_score_8h' => 0, 'sentiment_score_1d' => 0, 'sentiment_score_2d' => 0,
            'sentiment_score_3d' => 0, 'sentiment_score_1w' => 0, 'sentiment_score_2w' => 0,
            'sentiment_score_1m' => 0, 'sentiment_score_3m' => 0, 'sentiment_score_all' => 0,
            'articles_count_1h' => 1, 'articles_count_2h' => 1, 'articles_count_4h' => 1,
            'articles_count_8h' => 1, 'articles_count_1d' => 1, 'articles_count_2d' => 1,
            'articles_count_3d' => 1, 'articles_count_1w' => 1, 'articles_count_2w' => 1,
            'articles_count_1m' => 1, 'articles_count_3m' => 1, 'articles_count_all' => 1
        })
      end

      obj = mention.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == @tweet['user_tweeter_id'].to_i.to_s }.first
      unless obj
        mention.push(tweets: @tweet.select{|m| m.match(/^user_/)}.merge({'tweets' => []}))
        obj = mention.tweets.last
      end

      if obj['tweets'] && obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == @tweet_content['tweet_id'].to_i.to_s }.empty?
        obj['tweets'] << @tweet_content
      end

      begin
        obj['last_tweet_date'] = obj['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
      rescue Exception => e
        obj['last_tweet_date'] = Time.now.utc.iso8601(3)
      end

      # Update tweets_count
      mention['tweets_count'] = mention['tweets'].map{ |m| m['tweets'].count }.sum
      mention['tl_count'] = mention['tweets'].count
      mention['stats_all'] = mention['tl_count']
      mention['stats_1h'] = mention['stats_1h'] + 1

      mention.array_add_relation('articles', @article.pointer)
      mention.push(mention_score: mention_score(sentiment))
      mention['average_mention_score'] = mention['mention_score'].inject{ |sum, el| sum + el }.to_f / mention['mention_score'].size

      unless mention['sentiment_score']
        mention['sentiment_score'] = []
      end
      mention.push(sentiment_score: sentiment_score(sentiment))
      mention['sentiment_score_1h'] = Utils.get_avg_score(mention['sentiment_score'], 1.hour.ago)
      mention['sentiment_score_all'] = Utils.get_avg_score(mention['sentiment_score'])

      unless mention['wikipedia_url']
        if wikipedia_url
          mention['wikipedia_url'] = wikipedia_url
        else
          mention['wikipedia_url'] = get_wikipedia_url(name, type)
        end
      end

      unless mention['image_fetched']
        mention['image'] = get_google_image(name, type)
        mention['image_fetched'] = true
      end

      user = ThoughtLeader.new(id: @tweet['user_id']['objectId']).pointer

      # Add all user's networks to mention
      mention = add_networks(user, mention)

      # Add all user's industries to mention
      mention = add_industries(user, mention)

      @logger.info "Saving mention #{name} #{type} with #{mention['tl_count']} tl_count id #{mention.id}..."
      add_articles_count(mention)

      mention.save

      @article.array_add_relation('mentions', mention.pointer)

      @mentions << mention
    rescue Exception => e
      ApplicationController.error(@logger, "Fail adding mentions #{name} (#{type}) #{mention.id}", e)
    end
  end

  def add_articles_count(mention)
    count = MentionArticle.where(owningId: mention.id).count

    ranges = [
      { key: '1h', value: 1.hour.to_i   },
      { key: '2h', value: 2.hours.to_i  },
      { key: '4h', value: 4.hours.to_i  },
      { key: '8h', value: 8.hours.to_i  },
      { key: '1d', value: 1.day.to_i    },
      { key: '2d', value: 2.days.to_i   },
      { key: '3d', value: 3.days.to_i   },
      { key: '1w', value: 1.week.to_i   },
      { key: '2w', value: 2.weeks.to_i  },
      { key: '1m', value: 1.month.to_i  },
      { key: '3m', value: 3.months.to_i }
    ]

    time_check = Time.now.to_i - mention.created_at.to_i
    range = ranges.select {|r| time_check <= r[:value] }.first
    if range
      mention["articles_count_#{range[:key]}"] = count
    end

    mention['articles_count_all'] = count
  end

  def check_article(mentions)
    !mentions || (mentions.is_a?(Array) && mentions.select{|m| m['article_id'] == @article.id }.empty?)
  end

  def filter_sentiment
    @organizations.select!{|o| o[:sentiment] && (o[:sentiment] == 'P' || o[:sentiment] == 'P+')}
    @peoples.select!{|o| o[:sentiment] && (o[:sentiment] == 'P' || o[:sentiment] == 'P+')}
  end

  def get_mentions_data(o)
    {
      article_id: @article.id.to_s,
      relevance: o[:relevance],
      sentiment: o[:sentiment],
      mention_score: mention_score(o[:sentiment]),
      publisher_rank: @rank,
      categories: @article['Categories'],
      sub_categories: @article['SubCategories']
    }
  end

  def get_current_publisher_rank
    publisher = Publisher.where(publication_name: @article['publication_name']).first

    if publisher && publisher['rank']
      @rank = publisher['rank']
    else
      @rank = 2000000
    end
  end

  def mention_score(sentiment)
    score = sentiment_score_score(sentiment) * @mention_score
    (score ? score : 0)
  end

  # I love this little name
  def sentiment_score_score(sentiment)
    {
        'P+' => 3,
        'P' => 2,
        'NEU' => 1,
        'NONE' => 0,
        'N' => -2,
        'N+' => -3
    }[sentiment] || 0
  end

  def sentiment_score(sentiment)
    {
        date: Time.now.utc.iso8601(3),
        score: sentiment_score_score(sentiment)
    }
  end

  def get_wikipedia_url(name, type)
    url = nil
    begin
      require 'google/apis/customsearch_v1'
      search = Google::Apis::CustomsearchV1::CustomsearchService.new
      search.key = Settings.google.search_api_key
      result = nil
      query = "#{name} #{(name.split.size == 1 ? type : nil)} site:en.wikipedia.org"

      Retriable.retriable do
        result = search.list_cses(query,
                                  cx: Settings.google.search_engine_id,
                                  fields: 'items/link',
                                  num: 1
        )
      end

      url = result.items.first.link unless result.items.blank?
    rescue Exception => e
      ApplicationController.error(@logger, "Can't search for #{type} using q: \"#{query}\"", e)
    end
    url
  end

  def get_google_image(name, type)
    begin
      require 'google/apis/customsearch_v1'
      search = Google::Apis::CustomsearchV1::CustomsearchService.new
      search.key = Settings.google.search_api_key
      result = nil
      query = "#{name} #{type}"

      # Query returns one item only, just the link and type 'image'
      Retriable.retriable do
        result = search.list_cses(query,
                                  cx: Settings.google.search_engine_id,
                                  fields: 'items/link,items/image/height,items/image/width',
                                  num: 10,
                                  search_type: 'image',
                                  img_size: 'xlarge',
                                  # rights: 'cc_publicdomain|cc_sharealike'
        )
      end

      image = nil
      if result.items && !result.items.empty?
        # Loop through all images and try upload it
        Utils.order_images(result.items.select{|i| i.image.width >= 300 }).map do |i|
          image = "https://res.cloudinary.com/newsworthy/image/fetch/w_750,c_limit,q_auto/#{i.link}"
          break if image # Image uploaded, return url
        end
        image
      else
        nil # Return nil if no image returned
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Can't search for #{type} using q: \"#{query}\"", e)
    end
  end

  def upload_image(url, site_name, type)
    # Generate key for Cloudinary
    key = "#{Rails.env}/mentions/#{type}/#{Digest::MD5.hexdigest("#{url}#{site_name}")}/#{Digest::MD5.hexdigest(url)}"
    ret = nil
    begin
      resp = Cloudinary::Uploader.upload(url, public_id: key, tags: [Rails.env, 'mention'], width: 750, crop: :limit, quality: 80)
      # Return url
      ret = resp['url']
    rescue CloudinaryException => e
      @logger.warn("Cloudinary upload_image exception: #{e.message}")
    rescue Exception => e
      @logger.warn("Cant upload logo: #{e.message}")
    end

    ret
  end

  def add_networks(user, mention)
    @logger.info 'Add networks to mention...'

    # Add all user's networks to mention
    networks_ids = ThoughtLeaderNetwork.where(owningId: user.id.to_s).pluck(:relatedId)

    if networks_ids && !networks_ids.empty?
      Network.in(id: networks_ids).map do |n|
        # Don't need to check if network already exists, Parse do it for us
        mention.array_add_relation('Networks', n.pointer)

        # Add related Network to NetworkTweets
        # TODO: Migrate this stuff too
        net = MentionNetworkTweet.where(_p_Network: "Network$#{n.id}", _p_Mention:  "Mention$#{mention.id}").first

        unless net
          net = MentionNetworkTweet.create(
              {
                  'Network' => n.pointer,
                  'Mention' => mention.pointer,
                  'tweets' => [],
                  tweets_count: 1,
                  tl_count: 1,
                  'stats_1h' => 0, 'stats_2h' => 1, 'stats_4h' => 1,
                  'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                  'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                  'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1,
                  'sentiment_score' => [],
                  'sentiment_score_1h' => 0, 'sentiment_score_2h' => 0, 'sentiment_score_4h' => 0,
                  'sentiment_score_8h' => 0, 'sentiment_score_1d' => 0, 'sentiment_score_2d' => 0,
                  'sentiment_score_3d' => 0, 'sentiment_score_1w' => 0, 'sentiment_score_2w' => 0,
                  'sentiment_score_1m' => 0, 'sentiment_score_3m' => 0, 'sentiment_score_all' => 0
              }
          )
        end

        net.array_add_relation('mentions_articles', @article.pointer)

        obj = net.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == @tweet['user_tweeter_id'].to_i.to_s }.first
        unless obj
          net.push(tweets: @tweet.select{|m| m.match(/^user_/)}.merge({'tweets' => []}))
          obj = net.tweets.last
        end

        if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == @tweet_content['tweet_id'].to_i.to_s }.empty?
          obj['tweets'] << @tweet_content
        end

        begin
          obj['last_tweet_date'] = obj['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
        rescue Exception => e
          obj['last_tweet_date'] = Time.now.utc.iso8601(3)
        end

        # Update tweets_count
        net['tweets_count'] = net['tweets'].map{ |m| m['tweets'].count }.sum
        net['tl_count'] = net['tweets'].count
        net['stats_all'] = net['tl_count']
        net['stats_1h'] = net['stats_1h'] + 1

        unless net['sentiment_score']
          net['sentiment_score'] = []
        end
        net.push(sentiment_score: mention['sentiment_score'].last)
        net['sentiment_score_1h'] = Utils.get_avg_score(net['sentiment_score'], 1.hour.ago)
        net['sentiment_score_all'] = Utils.get_avg_score(net['sentiment_score'])

        net.save
      end
    end

    mention
  end

  def add_industries(user, mention)
    @logger.info 'Add industries to mention...'

    # Add all user's industries to mention
    industries_ids = ThoughtLeaderIndustry.where(owningId: user.id.to_s).pluck(:relatedId)

    if industries_ids && !industries_ids.empty?
      Industry.in(id: industries_ids).map do |n|
        mention.array_add_relation('Industries', n.pointer)

        # TODO: Migrate this stuff too
        net = MentionIndustryTweet.where(_p_Industry: "Industry$#{n.id}", _p_Mention:  "Mention$#{mention.id}").first

        unless net
          net = MentionIndustryTweet.create(
              {
                  'Industry' => n.pointer,
                  'Mention' => mention.pointer,
                  'tweets' => [],
                  tweets_count: 1,
                  tl_count: 1,
                  'stats_1h' => 0, 'stats_2h' => 1, 'stats_4h' => 1,
                  'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                  'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                  'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1,
                  'sentiment_score' => [],
                  'sentiment_score_1h' => 0, 'sentiment_score_2h' => 0, 'sentiment_score_4h' => 0,
                  'sentiment_score_8h' => 0, 'sentiment_score_1d' => 0, 'sentiment_score_2d' => 0,
                  'sentiment_score_3d' => 0, 'sentiment_score_1w' => 0, 'sentiment_score_2w' => 0,
                  'sentiment_score_1m' => 0, 'sentiment_score_3m' => 0, 'sentiment_score_all' => 0
              }
          )
        end

        net.array_add_relation('mentions_articles', @article.pointer)

        obj = net.tweets.select{|m| m['user_tweeter_id'].to_i.to_s == @tweet['user_tweeter_id'].to_i.to_s }.first
        unless obj
          net.push(tweets: @tweet.select{|m| m.match(/^user_/)}.merge({'tweets' => []}))
          obj = net.tweets.last
        end

        if obj['tweets'].select {|m| m['tweet_id'].to_i.to_s == @tweet_content['tweet_id'].to_i.to_s }.empty?
          obj['tweets'] << @tweet_content
        end

        begin
          obj['last_tweet_date'] = obj['tweets'].sort_by { |k| k['tweet_date'] }.last['tweet_date']
        rescue Exception => e
          obj['last_tweet_date'] = Time.now.utc.iso8601(3)
        end

        # Update tweets_count
        net['tweets_count'] = net['tweets'].map{ |m| m['tweets'].count }.sum
        net['tl_count'] = net['tweets'].count
        net['stats_all'] = net['tl_count']
        net['stats_1h'] = net['stats_1h'] + 1

        unless net['sentiment_score']
          net['sentiment_score'] = []
        end

        net.push(sentiment_score: mention['sentiment_score'].last)
        net['sentiment_score_1h'] = Utils.get_avg_score(net['sentiment_score'], 1.hour.ago)
        net['sentiment_score_all'] = Utils.get_avg_score(net['sentiment_score'])

        net.save
      end
    end

    mention
  end

  def calculate_ms(mp)
    sum = 0
    mp['mentions'].map do |m|
      sum += m['mention_score'] if m['mention_score']
    end
    total = sum.to_f / mp['mentions'].count
    Utils.get_float(total)
  end

  def calculate_as(mp)
    articles_ids = ArticleThoughtLeader.where(relatedId: mp.id).pluck(:owningId)

    score = 0

    if articles_ids && !articles_ids.empty?
      sum = 0
      Article.in(id: articles_ids).pluck(:score).map do |t|
        sum += t if t
      end
      score = sum.to_f / articles_ids.count
    end

    Utils.get_float(score)
  end

  def calculate_ns(mp)
    networks_ids = MentionedPersonNetwork.where(owningId: mp.id).pluck(:relatedId)

    score = 0

    if networks_ids && !networks_ids.empty?
      sum = 0
      Network.in(id: networks_ids).pluck(:score).map do |t|
        sum += t if t
      end
      score = sum.to_f / networks_ids.count
    end

    Utils.get_float(score)
  end

  def calculate_score(mp)
    total = (mp['average_mention_score'] + ((mp['average_article_score'] + mp['average_network_score']) / 2.to_f))
    Utils.get_float(total, 1)
  end

  def calculate_mention_score
    # MS = S x (1+ (100/P)) x ((sum(Ts1, Ts2, Ts3)/ACS))
    @mention_score = 1 + (100 / @rank.to_f)
    tls_ids = ArticleThoughtLeader.where(owningId: @article.id).pluck(:relatedId)

    if tls_ids && !tls_ids.empty?
      sum = 0
      ThoughtLeader.in(id: tls_ids).pluck(:score).map do |t|
        sum += t if t
      end
      @mention_score = @mention_score * (sum.to_f / @article['tl_count'])
    end
  end

  def add_mention_relations
    @mentions.map do |m|
      @mentions.map do |m2|
        if m.id != m2.id
          unless check_mention_to_mention(MentionToMention, m.id, m2.id)
            MentionToMention.create(
                {
                    Mention: m.pointer,
                    RelatedMention: m2.pointer
                }
            )
          end


          MentionNetwork.where(owningId: m.id).each do |n|
            unless check_mention_to_mention(MentionToMentionNetwork, m.id, m2.id, n.relatedId, 'Network')
              MentionToMentionNetwork.create(
                  {
                      Mention: m.pointer,
                      RelatedMention: m2.pointer,
                      Network: Network.new(id: n.relatedId).pointer
                  }
              )
            end
          end

          MentionIndustry.where(owningId: m.id).each do |i|
            unless check_mention_to_mention(MentionToMentionIndustry, m.id, m2.id, i.relatedId, 'Industry')
              MentionToMentionIndustry.create(
                  {
                      Mention: m.pointer,
                      RelatedMention: m2.pointer,
                      Industry: Industry.new(id: i.relatedId).pointer
                  }
              )
            end
          end
        end
      end
    end
  end

  def check_mention_to_mention(class_obj, id, id2, id3 = false, field = nil)
    if id3
      if field == 'Industry'
        return true if class_obj.where(_p_Mention: "Mention$#{id}", _p_RelatedMention:  "Mention$#{id2}", _p_Industry: "Industry$#{id3}").exists?
        return true if class_obj.where(_p_Mention: "Mention$#{id2}", _p_RelatedMention:  "Mention$#{id}", _p_Industry: "Industry$#{id3}").exists?
      else
        return true if class_obj.where(_p_Mention: "Mention$#{id}", _p_RelatedMention:  "Mention$#{id2}", _p_Network: "Network$#{id3}").exists?
        return true if class_obj.where(_p_Mention: "Mention$#{id2}", _p_RelatedMention:  "Mention$#{id}", _p_Network: "Network$#{id3}").exists?
      end
    else
      return true if class_obj.where(_p_Mention: "Mention$#{id}", _p_RelatedMention:  "Mention$#{id2}").exists?
      return true if class_obj.where(_p_Mention: "Mention$#{id2}", _p_RelatedMention:  "Mention$#{id}").exists?
    end
    false
  end
end
