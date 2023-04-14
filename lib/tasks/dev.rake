# Used for dev purpose

# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

namespace :dev do
  task :cloudinary_upload => :environment do
    data = {
        images: [
            {url: 'http://res.cloudinary.com/demo/image/upload/w_250,h_168,c_fit/sample.jpg'},
            {url: 'https://www.forrester.com/pimages/forrester/imported/forresterDotCom/Research/122102/122102_2.gif'},
            {url: 'https://res.cloudinary.com/demo/image/upload/sample.jpg'},
            {url: 'http://wtf'}
        ],
        publication_name: 'test.upload.com',
        title: 'Test Upload'
    }

    images = []

    data[:images].each do |i|
      key = "#{data[:publication_name]}/#{Digest::MD5.hexdigest("#{i[:url]}#{data[:title]}")}/#{Digest::MD5.hexdigest(i[:url])}"
      begin
        resp = Cloudinary::Uploader.upload(i[:url], public_id: key, tags: Rails.env, quality: 80)
        if resp['width'] < 300
          Cloudinary::Uploader.destroy(key)
        else
          images << { url: resp['url'], key: key }
        end
      rescue CloudinaryException => e
        p e
        # http error or something
      end
    end
  end

  task :url_test => :environment do
    urls = %w(http://www.forbes.com/sites/laurashin/2015/09/09/bitcoins-shared-ledger-technology-moneys-new-operating-system/?utm_campaign=forbes&utm_source=twitter&utm_medium=social&utm_channel=investing&linkid=16919371 http://nyti.ms/1OcKzhw http://www.prq.se/?p=company&intl=1)
    urls.each do |u|
      begin
        agent = Mechanize.new do |agent|
          agent.user_agent_alias = 'Mac Safari'
          agent.follow_meta_refresh = true
          agent.keep_alive = false
          agent.ignore_bad_chunking = true
        end
        page = agent.get(u)
        url_1 = page.uri.to_s
        url_2 = page.uri.to_s.gsub("?#{page.uri.query}", '').gsub("##{page.uri.fragment}", '')
        if url_1 == url_2
          url = url_2
        else
          md5_1 = Digest::MD5.hexdigest(Biffbot::Analyze.new(url_1)['objects'].first['text'])
          md5_2 = Digest::MD5.hexdigest(Biffbot::Analyze.new(url_2)['objects'].first['text'])
          if md5_1 == md5_2
            url = url_2
          else
            url = url_1
          end
        end
      rescue Exception => e
        p e
      ensure
        agent.shutdown
      end
    end
  end

  task :change_linkis => :environment do
    start_time = Time.now
    Rails.logger.info "Start change_linkis at #{start_time.strftime('%H:%M:%S')}..."

    ids = %w(f6n0cnNMMJ p96bahyucE rzMd7k7OZn VV7jl2L7gT)
    ids.each do |i|
      begin
        Retriable.retriable do
          obj = Parse::Query.new('Article').tap do |q|
            q.eq('objectId', i)
          end.get.first

          unless obj
            Rails.logger.info "Fail get obj on get_linkis_url for #{i}"
            next
          end

          begin
            page = MetaInspector.new(obj['url'], {
                                            connection_timeout: 15,
                                            read_timeout: 15,
                                            faraday_options: { ssl: { verify: :none }}
                                        })
            if page.response.status == 200
              url = get_linkis_url(obj['url'])
              if url
                obj['url'] = url
                obj.save
                Rails.logger.info "Object saved with new url #{url}"
              else
                Rails.logger.info "Fail get url on get_linkis_url for #{i}"
              end
            else
              Rails.logger.info "Fail get og:url on get_linkis_url for #{i}"
            end
          rescue Exception => e
            Rails.logger.info "Fail get og:url on get_linkis_url from #{i}: #{e.class} - #{e.message}"
          end
        end
      rescue Exception => e
        Rails.logger.info "[change_linkis] Can't get Parse object: #{e.class} - #{e.message}"
      end
    end
  end

  task :content => :environment do
    # FetchContent.perform_now('747419832056844291', 'monce')

    objects = []
    Mention.only(:articles_count).map do |m|
      count = MentionArticle.where(owningId: m.id).count
      if m['articles_count'] != count
        p "Mention #{m.id} count differ: #{m['articles_count']} <=> #{count}"
        # objects << { update_one: { filter: { _id: m.id }, update: { '$set' => { articles_count: count }}}}
        # Mention.find(m.id).update(articles_count: count)
      end
    end

    if objects.count > 0
      ret = class_name.constantize.collection.bulk_write(objects)
      p ret
    end

    Mention.where(articles_count: 0).destroy_all
    users = {}

    NetworkTweet.only(:tweets).all.map do |o|
      if o['tweets']
        changed = false
        o['tweets'].map do |t|
          unless t['user_id']
            if users[t['user_tweeter_id']]
              t['user_id'] = users[t['user_tweeter_id']]
            else
              user = ThoughtLeader.where(twitter_id: t['user_tweeter_id'].to_s).first
              p "No user for #{t['user_tweeter_id']}" and next unless user

              t['user_id'] = user.pointer.to_h
              users[t['user_tweeter_id']] = user.pointer.to_h
            end
            changed = true
          end
        end
        if changed
          p "Update #{o.id}"
          NetworkTweet.find(o.id).update(tweets: o['tweets'])
        end
      else
        p "No tweets for #{o.id} %-|"
      end
    end

    # Article.only(:content).where(md5_content: nil).map do |a|
    #   Article.find(a.id).update(md5_content: Digest::MD5.hexdigest(a.content))
    # end
    #
    # AddEntities.perform_now('576b40caeac90b67d5b93235', '718270981215797200', true, 666)
    # ids = %w(gRTBtWrDhZ BsxhOFFAna RQktwcFnNn thczyF7YDz GTDBWi48Gm sfklJzRtjm vGlcpEwYHp 5OP63BHgBw 3wPljpS4EA DkSKe6tlVD u47pEnwB68 aQDB0OZjP0 6vQIouNCSN LcQqlWSQTM sCZ2KtDZKS GOmDdnWR6v DKAMJKgOBX 6AJWMPuQmV lgAjgC5153 7sr3vCcEqb XAIG2mnQVI 98BHvfwTFH SdkaSw6PH9 6KO2df33sm jfCiZvaZU4 RPUWzddW4C LL1KZG7tdR NLZk1mqo4w QOZJh76aeE g3KXdKWPmr f2IztDvqH4 NaJCt2RNYR EC2A83PF6q KWSdvHFEtF DaTa7MxfkR mh8aD9YRVm LA6AwbCuju YnWGhImX72 cbBtB9DGGT HIIwYwQAA1 2o4doWAk8h pWhNCihtA4 I4u9WCz0bM RxT9VxVWNq w24gGX3P0N F9YJ4QtYMx LtmtQHQV0u q2I5FCtGH9 zTdgV6oYdE ayqtYO7sqD oDkROgawRl LiUUQImqmn 1hSzgDPs9A kX4w2O4EvY hzKERmbv0p FEDBjA1zZz qNAnGOASXM 6JR8ctlpUc GNnXjmEpxB mqYR5EQbDz nfLK6vyoPF JJ3xTn5rIP 3vGQ0KKF1k agtbNMmQut IgnuuKi0zl wikxhZLjnd i3qeD9zCZc rQMrjymhHn 98zfVXKya6 H685T997s4 Azua6J9yRO 6DV2DUKk0e 5EoBT9sIR4 eo3B25pcAl GXrAjoW2yx kBAg28nH5Z GFjIPQ3t8X DPzeRC6rnz dPX1V5BxIy 2V0X5pe75w oJKptNC9OS DQvo2af7N7 E7PY4mGFJ9 VNAPdqoXYB 89dCVzgmcL WRXZAovY7H W5M5V0J38D pg7jYeRor4 zLULu8GlFF v5uIkki20k qgxwPB6yKv i4v1sr7pyx cZTW2IxDEW bGIxGzt8PS PqcbNaf2X7 laYyJTxJXh nIEwFFscjk 7i2Kwb7xao I2EO0WZDPZ O3fwn9ryIS uzRS4MtG3f iwJnurqv7U RXyBBja7Yl XUwAcXc37s T7UvpHKg8I nDZFV0sHIq UinaIDUMti 3VABOflLXz UNhOH4BabW 7LdTUkWMCt Eryn1mHE4d RDeQXnZ5bX FPbWsoH6WD SViYpkRos7 6M6angclBj BuOrdFC2Ae GfVtQI8iKO jdLuJezOfw atThsF3opZ R0v8wk8dNb fe6AJsTddv 0J5pGAJf5G IteSBJIdGx 8qJd2AGLiE 8wpscMzQcI y4nvTetqYO G7tTPLG29J try2vmAHwH l5oTlN0wN8 AvfCnOTYHF 4cU4zMcD6i wHoH5vJu7k rmRZZWxGAr 6w1GMIvhig lSJ8wp85WD jKU1wZ1zZQ 4A9j7i102I jhCjX7n06u TMPa1yvQ0Y 1ZcP2frpiA uQevNsaqrV jrWJIRmrJX mTh7a2eyW7 54xji9AhQ6 4dobOeaZTv 0K3w6Zyoey LSxuwtNWDu neRXyKSIFA 83xW0LFY07 KvnZekXdO9 Vyhxo2LLqp pf6aT3HqJR sHtdJnnink xdGQwCm9NW uuNLAPXod1 pZHG8e0AbX wE5H2uzPg2 2uGgZUpTc6 NyPArR49cx rKapCZxUJM 1VqICnHwpx jtztrRzcKo kbR0rOc4MA hAnbybAmyG l0HMfS8TYH y9Nlt6IWGL 384zjTHKJF negVCLDoMh yMzajSXUoo TllI5PbpXC XkcHBj1e2x CibhWf59OA FH6YAqdrw6 XpH1NoTMCV UxGSlki3Ku KeiAKgsAi7 Jnw6TaHpRi 2F2uio7OF9 c8EnpFBBGE t028UgT0po CddmGGU13Z Y4GhI7mPY4 62tvOxM7bY r01oXUSCgU FmAduWQxXR v8tCICq3Mm 3urONEF6Rx t2zonjgjZb TZ6ZLMawN9 Og1RgX3KAk WKHuOzTytp TlhnXq1ksc XtUavOAOUi 2EnxkcS3tE ewnqMvb20i gRvymZophP 1mJn2zSxDj mvcRCOlGjN CI4RFM1TDk 1ACbLvoWiu gi12fV7PD1 MT2cWdT3gg 6BHfztOz4M kR1985rITI hjL5xunBln vDtLgc53mw EWyp7MbnnA PzS3FD0AdN aSLOBvnS5J sBx7S6QGIa LjmgdxB1MJ 63MWldM5BQ IOmGnoKRd6 aZaopeskn2 ZdyisM2Df5 pDA2FxHVwb XYdznnVrcL G08p1OnQJR ClPuc8VWeB 1Ffk5QvcGA W7idFwSy2k NXmP6Kr3nt 7V3vOU6Iry Ms6EpLbxeZ ROBfGcuTbt eMcfTX53pP pC6NAD9m4W fumv7YFcTm cJ8vBhJTir nzS0TMDNpB TqCOLieQeQ)
    #
    # Mention.all.map do |m|
    #   if m.sentiment_score_3m.is_a?(Float) &&  m.sentiment_score_3m.nan?
    #     m.update(                  'sentiment_score_1h' => 0, 'sentiment_score_2h' => 0, 'sentiment_score_4h' => 0,
    #                                'sentiment_score_8h' => 0, 'sentiment_score_1d' => 0, 'sentiment_score_2d' => 0,
    #                                'sentiment_score_3d' => 0, 'sentiment_score_1w' => 0, 'sentiment_score_2w' => 0,
    #                                'sentiment_score_1m' => 0, 'sentiment_score_3m' => 0, 'sentiment_score_all' => 0)
    #   end
    # end

    # ids.map do |i|
    #   o = Article.only('tweets').where(id: i).first
    #   if o
    #     begin
    #       tweet_id = o.tweets.last['tweets'].last['tweet_id']
    #       AddEntities.perform_later(i, tweet_id)
    #     rescue Exception => e
    #       p e.message
    #       pp e.backtrace
    #     end
    #   end
    # end

    # Settings.streamers.map do |s|
    #   proxy = "http://#{Settings.proxies.delete(Settings.proxies.sample)}"
    #   UpdateTl.perform_now(s.to_h, proxy)
    # end
    # GetPublisher.perform_now('ourworldindata.org', '', false, false, true)
    # GetUserInformation.perform_now('M1pj4VgBJw', 'ThoughtLeader', {twitter: 'ericschmidt'})

    # Settings.streamers.select{|s| s.topic.parameterize == 'sport'}.map do |s|
    #   streamer = Streamer.where(topic: s.topic.parameterize).first
    #   puts "no streamer for #{s.topic.parameterize}" and next unless streamer
    #
    #   proxy = "http://#{Settings.proxies.sample}"
    #   client = Utils.twitter_client(s, proxy)
    #
    #   cursor = -1
    #   count = 0
    #   updated = 0
    #   begin
    #     response = client.friend_ids(cursor: cursor)
    #     cursor = response.attrs[:next_cursor]
    #     puts "Update information for #{s[:topic]} with #{response.count} TLs..."
    #     response.map do |u|
    #       count += 1
    #       tl = ThoughtLeader.where(twitter_id: u.to_s).first
    #       if tl
    #         tl.update(streamer: streamer)
    #         updated += 1
    #       else
    #         puts "Can't find tl #{u} in database"
    #       end
    #     end
    #     puts "#{updated} TLs"
    #   rescue Exception => e
    #     puts "Fail to get information for #{s[:topic]} (#{cursor} #{count} #{updated})"
    #     puts e.message
    #     cursor = -1
    #   end while cursor && cursor > 0
    # end
    #
    # tls_ids = ThoughtLeader.only(:id).where(identified_by_mention: false).pluck(:id)
    #

    models = %w(ArticleMention ArticleMpMention ArticleNetwork ArticleNetworkMention ArticleThoughtLeader ArticleIndustry ArticleTlMention MentionArticle UserNetwork MentionIndustry MentionIndustryTweetArticle MentionNetwork MentionNetworkTweetArticle MentionedPersonIndustry MentionedPersonNetwork ThoughtLeaderNetwork ThoughtLeaderIndustry UserIndustry)

    models.map do |m|
      p "Model #{m}"
      m.constantize.all.map do |s|
        m.constantize.where(owningId: s.owningId, relatedId: s.relatedId).drop(1).map{|m2| m2.destroy }
      end
    end

    MentionNetworkTweetArticle.all.map do |m|
      MentionNetworkTweetArticle.where(owningId: m.owningId, relatedId: m.relatedId).drop(1).map{|m2| m2.destroy }
    end

    object.attributes.to_a.each do |k,v|
      if v && schema[k]
        match = schema[k].match(/^\*(.*)/) # match '*Model'

        if match && match[1]
          p "#{k} #{v} #{match[1]}"
        end
      end
    end

    object.attributes.to_a.each do |k,v|
      if v && schema[k]
        match = schema[k].match(/^\*(.*)/) # match '*Model'

        if match && match[1]
          p "#{k} #{v} #{match[1]}"
        end
      end
    end

    ThoughtLeader.where(identified_by_mention: true).map do |t|
      mp = MentionedPerson.where(twitter_id: t['twitter_id']).find_or_create_by(
          {
              Hidden: true,
              InformationFetched: true,
              TwitterURL: t['TwitterURL'],
              avatar: t['avatar'],
              average_article_score: 0,
              average_network_score: 0,
              average_mention_score: 0,
              country: t['country'],
              display_name: t['display_name'],
              language: t['language'],
              mentions: t['mentions'],
              name: t['name'],
              profile_updated_at: t['profile_updated_at'],
              score: 0,
              summary: t['summary'],
              twitter_id: t['twitter_id'],
              LinkedinURL: t['LinkedinURL'],
              JobTitle: t['JobTitle'],
              disabled: t['disabled']
          }
      )

      ArticleTlMention.where(relatedId: t.id).map do |o|
        ArticleMpMention.find_or_create_by({owningId: o.owningId.to_s, relatedId: mp.id.to_s})
      end

      ThoughtLeaderIndustry.where(owningId: t.id).map do |o|
        MentionedPersonIndustry.find_or_create_by({owningId: mp.id.to_s, relatedId: o.relatedId.to_s})
      end

      ThoughtLeaderNetwork.where(owningId: t.id).map do |o|
        MentionedPersonNetwork.find_or_create_by({owningId: mp.id.to_s, relatedId: o.relatedId.to_s})
      end
    end

    ThoughtLeader.where(identified_by_mention: true).map do |t|
      mp = MentionedPerson.where(twitter_id: t['twitter_id']).first
      p "not for #{t['twitter_id']}" unless mp
    end
    #
    # ThoughtLeader.where(identified_by_mention: true).destroy_all
    #
    # MentionedPerson.all.map do |m|
    #   m.update(TwitterURL: "https://twitter.com/#{m.name}")
    # end
    #
    # ids = MentionedPerson.only(:id).all.pluck(:id)
    #
    # count = 0
    #
    # MentionedPersonIndustry.all.map do |m|
    #   unless ids.include?(m.owningId.to_s)
    #     puts "delete #{m.id}"
    #     m.destroy
    #   end
    # end
    #
    # MentionedPersonNetwork.all.map do |m|
    #   unless ids.include?(m.owningId.to_s)
    #     puts "delete #{m.id}"
    #     m.destroy
    #   end
    # end
    #
    # %w(Mention MentionIndustryTweet MentionNetworkTweet).map do |m|
    #   m.constantize.all.map do |o|
    #     o.update(sentiment_score_all: Utils.get_avg_score(o['sentiment_score']))
    #   end
    # end
  end

  task :fix_mention => :environment do
    start_time = Time.now
    Rails.logger.info "Start fix_mention stats at #{start_time.strftime('%H:%M:%S')}..."

    ids = []
    ThoughtLeader.all.map do |t|
      unless ids.include?(t['twitter_id'])
        ids << t['twitter_id']
        count = ThoughtLeader.where(twitter_id: t['twitter_id']).count
        if count > 1
          tl = ThoughtLeader.where(twitter_id: t['twitter_id'], mentions_count: 0).first
          if tl
            tl.destroy
            puts "deleted #{tl.id} #{t['twitter_id']}"
          else
            puts "not found #{count} #{t['twitter_id']}"
          end
        end
      end
    end

    # Check TL integrity
    ThoughtLeaderNetwork.all.map do |t|
      count = ThoughtLeader.where(id: t['owningId']).count
      if count == 0
        puts "delete #{t['id']}"
      end
    end

    ThoughtLeaderIndustry.all.map do |t|
      count = ThoughtLeader.where(id: t['owningId']).count
      if count == 0
        puts "delete #{t['id']}"
      end
    end

    ArticleThoughtLeader.all.map do |t|
      count = ThoughtLeader.where(id: t['relatedId']).count
      if count == 0
        puts "delete #{t['id']}"
      end
    end

    ArticleTlMention.all.map do |t|
      count = ThoughtLeader.where(id: t['relatedId']).count
      if count == 0
        puts "delete #{t['id']}"
      end
    end

    Search.where(EntityType: 'ThoughtLeaders').map do |t|
      count = ThoughtLeader.where(id: t['EntityId']).count
      if count == 0
        puts "delete #{t['id']}"
      end
    end

    # Update search for Tl
    Search.where(EntityType: 'ThoughtLeaders').map do |t|
      tl = ThoughtLeader.where(id: t['EntityId']).first
      if tl
        puts "save #{t['id']} #{tl['avatar']}"
        t.update({
                     EntityMedia: tl['avatar'],
                     EntityName: tl['display_name'],
                     EntityNameLC: tl['display_name'].downcase
                 })
      else
        puts "what?? #{t['EntityId']}"
      end
    end

    Mention.all.limit(100).map do |m|
      tweets = []
      MentionIndustryTweet.where(_p_Mention: "Mention$#{id}").map do |o|
        o['tweets'].map do |t|
          if tweets.empty? || tweets.select{|ts| ts['tweet_id'] == t['tweet_id'] }.empty?
            tweets << t
          end
        end
      end
      MentionNetworkTweet.where(_p_Mention: "Mention$#{id}").map do |o|
        o['tweets'].map do |t|
          if tweets.empty? || tweets.select{|ts| ts['tweet_id'] == t['tweet_id'] }.empty?
            tweets << t
          end
        end
      end

      if tweets.count != m['tweets'].count
        Article.in(id: MentionArticle.where(owningId: m.id).pluck(:relatedId)).map do |o|
          o['tweets'].map do |t|
            if tweets.empty? || tweets.select{|ts| ts['tweet_id'] == t['tweet_id'] }.empty?
              tweets << t
            end
          end
        end
        if tweets.count != m['tweets'].count
          puts "mismatch tweets count for #{m.id}"
        end
      end
    end

    Rails.logger.info "Task fix_mention in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :test => :environment do
    start_time = Time.now
    puts "-> Start updating stats at #{start_time.strftime('%H:%M:%S')}..."

    # AddEntities.perform_now('SpZlr7NlpP', true, 666)
    # GetPublisher.perform_now('Talawa', 'talawa.fr')
    GetUserInformation.perform_now('5769f403c951662ea4b41e53', 'MentionedPerson', {twitter: 'Wickiliks'})

    puts "-> Updated stats in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_users => :environment do
    # Old task to update ThoughtLeaders & Users informations from Pipl and FullcontactApi

    start_time = Time.now
    Rails.logger.info "Start update_users at #{start_time.strftime('%H:%M:%S')}..."

    Rails.logger.info 'Fetching Users...'
    users = Parse::Query.new('_User').tap do |q|
      q.limit = 1000
    end.get

    Rails.logger.info "Found #{users.count} Users"

    users.each do |u|
      GetUserInformation.perform_later(u.id.to_s, 'User',
                                                                 {
            email: u['email'],
            name: u['FullName'],
            twitter: u['TwitterUsername']
        }
      )
    end

    Rails.logger.info 'Fetching ThoughtLeaders...'
    tl = Parse::Query.new('ThoughtLeaders').tap do |q|
      q.limit = 100
      q.skip = 450
    end.get

    Rails.logger.info "Found #{tl.count} ThoughtLeaders"

    tl.each do |u|
      GetUserInformation.perform_later(u.id.to_s, 'ThoughtLeader',
                                                                 {
            name: u['display_name'],
            twitter: u['name']
        }
      )
    end

    Rails.logger.info "Users updated in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_networks => :environment do
    # Old task to update Networks information

    start_time = Time.now
    Rails.logger.info "Start update_networks at #{start_time.strftime('%H:%M:%S')}..."

    Rails.logger.info 'Fetching Networks...'
    tl = Parse::Query.new('Network').tap do |q|
      q.limit = 1000
    end.get

    Rails.logger.info "Found #{tl.count} Networks"

    tl.each do |u|
      GetNetworkInformation.perform_later(u.id.to_s)
    end

    tl = Parse::Query.new('Network').tap do |q|
      q.limit = 1000
      q.skip = 1000
    end.get

    Rails.logger.info "Found #{tl.count} Networks"

    tl.each do |u|
      GetNetworkInformation.perform_later(u.id.to_s)
    end

    Rails.logger.info "Networks updated in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_search => :environment do
    # Add Networks, Publishers & ThoughtLeaders to Search

    start_time = Time.now
    Rails.logger.info "Start update_networks at #{start_time.strftime('%H:%M:%S')}..."

    Rails.logger.info 'Fetching Networks...'
    res = Parse::Query.new('Network').tap do |q|
      q.limit = 1000
      q.skip = 1000
      q.eq('InformationFetched', true)
    end.get

    Rails.logger.info "Found #{res.count} Networks"

    res.each do |u|
      Rails.logger.info "Add Network \"#{u['NetworkName']}\" to Search Class"

      search = nil
      Retriable.retriable do
        search = Parse::Query.new('Search').tap do |q|
          q.eq('EntityType', 'Network')
          q.eq('EntityName', u['NetworkName'])
        end.get.first
      end

      if search
        search['EntityMedia'] = u['IconURL']
        Retriable.retriable do
          search.save
        end
      else
        Retriable.retriable do
          Parse::Object.new('Search', {
              EntityId: u['objectId'],
              EntityType: 'Network',
              EntityName: u['NetworkName'],
              EntityMedia: u['IconURL'],
              Network: u.pointer
          }).save
        end
      end
    end

    Rails.logger.info 'Fetching Publishers...'
    res = Parse::Query.new('Publisher').tap do |q|
      q.limit = 1000
      q.skip = 2000
      q.eq('fetched', true)
    end.get

    Rails.logger.info "Found #{res.count} Publishers"

    res.each do |obj|
      Rails.logger.info "Add Publisher \"#{obj['site_name']}\" to Search Class"

      search = nil
      Retriable.retriable do
        search = Parse::Query.new('Search').tap do |q|
          q.eq('EntityType', 'Publisher')
          q.eq('EntityName', obj['site_name'])
        end.get.first
      end

      unless search
        Retriable.retriable do
          Parse::Object.new('Search', {
              EntityId: obj['objectId'],
              EntityType: 'Publisher',
              EntityName: obj['site_name'],
              EntityMedia: obj['icon'],
              Publisher: obj.pointer
          }).save
        end
      end
    end

    Rails.logger.info 'Fetching ThoughtLeaders...'
    res = Parse::Query.new('ThoughtLeaders').tap do |q|
      q.limit = 1000
      q.eq('InformationFetched', true)
    end.get

    Rails.logger.info "Found #{res.count} ThoughtLeaders"

    res.each do |obj|
      Rails.logger.info "Add ThoughtLeaders \"#{obj['display_name']}\" to Search Class"

      search = nil
      Retriable.retriable do
        search = Parse::Query.new('Search').tap do |q|
          q.eq('EntityType', 'ThoughtLeaders')
          q.eq('EntityName', obj['display_name'])
        end.get.first
      end

      unless search
        Retriable.retriable do
          Parse::Object.new('Search', {
              EntityId: obj['objectId'],
              EntityType: 'ThoughtLeaders',
              EntityName: obj['display_name'],
              EntityMedia: obj['avatar'],
              ThoughtLeaders: obj.pointer
          }).save
        end
      end
    end
  end

  task :create_industry => :environment do
    start_time = Time.now
    Rails.logger.info "Start create_industry at #{start_time.strftime('%H:%M:%S')}..."

    Rails.logger.info 'Fetching Networks...'
    tl = Parse::Query.new('Network').tap do |q|
      q.limit = 1000
      q.not_eq('Industry', nil)
    end.get

    Rails.logger.info "Found #{tl.count} Networks"

    tl.each do |u|
      ind = nil
      Retriable.retriable do
        ind = Parse::Query.new('Industry').tap do |q|
          q.eq('IndustryNameLC', u['Industry'].downcase)
        end.get.first
      end

      unless ind
        ind = Parse::Object.new('Industry', {
            IndustryName: u['Industry'],
            IndustryNameLC: u['Industry'].downcase,
            IconURL: nil
        })
        Rails.logger.info "Create #{u['Industry']}"
        Retriable.retriable do
          ind.save
        end

        search = nil
        Retriable.retriable do
          search = Parse::Query.new('Search').tap do |q|
            q.eq('EntityType', 'Industry')
            q.eq('EntityName', ind['IndustryName'])
          end.get.first
        end

        unless search
          Retriable.retriable do
            Parse::Object.new('Search', {
                EntityId: ind['objectId'],
                EntityType: 'Industry',
                EntityName: ind['IndustryName'],
                EntityMedia: ind['IconURL'],
                Industry: ind.pointer
            }).save
          end
        end
      end

      Rails.logger.info "Save #{u['NetworkName']} with #{u['Industry']}"

      u['Industry'] = ind.pointer
      Retriable.retriable do
        u.save
      end
    end
  end

  task :delete_orphans => :environment do
    start_time = Time.now
    Rails.logger.info "Start delete_orphans at #{start_time.strftime('%H:%M:%S')}..."

    @article_ids = []

    %w(NetworkTweets IndustryTweets).map do |class_name|
      created_at = 99.years.ago
      run = true
      elem = 0

      main_class = class_name.gsub('Tweets', '')
      instance_variable_set("@#{main_class.downcase}_ids", [])

      while run do
        Rails.logger.info "   Get the ##{elem} #{class_name}. Created at: #{created_at}"
        ret = nil
        Retriable.retriable do
          ret = Parse::Query.new(class_name).tap do |q|
            q.limit = 1000
            q.skip = 0
            q.order_by = 'createdAt'
            q.greater_than('createdAt', Parse::Date.new(created_at))
          end.get
        end

        if ret.empty? || ret.count <= 0
          Rails.logger.info "   Find limits for #{class_name}: #{ret.count}. Break loop..."
          run = false
        else
          ret.map do |o|
            elem += 1
            ['Article', main_class].map do |test_class|
              data_array = instance_variable_get("@#{test_class.downcase}_ids")
              next if (!o[test_class] || data_array.include?(o[test_class].id))

              obj = nil

              Retriable.retriable do
                obj = Parse::Query.new(test_class).eq('objectId', o[test_class].id).get.first
              end

              if obj
                data_array << o[test_class].id
              else
                Rails.logger.info " > Delete object #{class_name} #{o.id} missing #{test_class} #{o[test_class].id}"
                Retriable.retriable do
                  o.parse_delete
                end
                break
              end
            end
          end
          created_at = ret.last['createdAt']
        end
      end
    end

    Rails.logger.info "Finished delete_orphans in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end

def get_linkis_url(url)
  begin
    page = MetaInspector.new(url, {
                                    connection_timeout: 15,
                                    read_timeout: 15,
                                    faraday_options: { ssl: { verify: :none }}
                                })
    if page.response.status == 200
      html_doc = Nokogiri::HTML(page.to_s)

      elem = html_doc.xpath('//a[contains(@class, "js-source-link")]')
      unless elem.empty?
        return (elem.first.text =~ /^https?:\/\// ? elem.first.text : "http://#{elem.first.text}")
      end
      elem = html_doc.xpath('//a[contains(@class, "js-original-link")]')
      unless elem.empty?
        return (elem.first.text =~ /^https?:\/\// ? elem.first.text : "http://#{elem.first.text}")
      end

      return page.meta_tags['property']['og:url'].first
    else
      ApplicationController.error(@logger, "Fail get og:url on get_linkis_url from #{url}", e)
      return nil
    end
  rescue Exception => e
    ApplicationController.error(@logger, "Fail retry get_linkis_url #{url}", e)
    return nil
  end
end

def get_article_content(obj)
  return obj['text'] unless obj['html']

  html_doc = Nokogiri::HTML(obj['html'])

  return obj['html'] unless html_doc.at('body')

  # removing all first images and \n
  html_doc.at_css('body').traverse do |e|
    if e.name == 'img' || e.name == 'figure' || e.name == 'figcaption' || e.parent.name == 'img' || e.parent.name == 'figure' || e.parent.name == 'figcaption' || (e.parent.name == 'a' && e.parent.parent.name == 'figcaption')
      e.remove
    elsif e.text.size <= 2
      e.remove
    else
      break
    end
  end

  images = html_doc.search('img')
  return html_doc.search('body').children.to_html if images.count < 1

  elem = images.first
  count = 0
  html_doc.at_css('body').traverse do |e|
    break if e.object_id == elem.object_id
    count += e.text.size if e.text.size > 2
    break if count > 100
  end

  if count <= 100
    elem = find_image_element(elem, true)
    elem.remove
  end

  html_doc.search('body').children.to_html.gsub(/^\n/,'')
end

def find_image_element(elem, first = false)
  if elem.parent.name == 'a' && elem.parent.parent.name == 'figure' && (first || elem.parent.parent.search('img').count == 1)
    elem.parent.parent
  elsif elem.parent.name == 'figure' && elem.parent.parent.name == 'aside' && (first || elem.parent.parent.search('img').count == 1)
    elem.parent.parent
  elsif elem.parent.name == 'figure' && (first || elem.parent.search('img').count == 1)
    elem.parent
  else
    elem
  end
end
