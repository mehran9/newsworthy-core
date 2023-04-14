# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

namespace :update_networks do
  task :change => :environment do
    # Change way the networks are, so big update

    start_time = Time.now
    Rails.logger.info "Start updating networks at #{start_time.strftime('%H:%M:%S')}..."

    Rails.logger.info 'Get all ThoughtLeaders...'
    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('ThoughtLeaders').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_networks:change] Can't fetch ThoughtLeaders", e)
    end

    Rails.logger.info 'No ThoughtLeaders to update. Exiting...' and next if !count || count['count'] == 0

    limit = (Rails.env.development? ? 10 : 1000)
    pages = count['count'].fdiv(limit).floor
    tl = []
    Rails.logger.info "Find #{count['count']} ThoughtLeaders with max #{limit} per page, so looping for #{pages + 1} pages"

    Parallel.each(0..pages, in_threads: 1) do |i|
      begin
        Rails.logger.info "Get ThoughtLeaders from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('ThoughtLeaders').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          ret.each do |a|
            networks = Parse::Query.new('Network').tap do |q|
              q.related_to('Networks', a.pointer)
            end.get
            a['Networks'] = networks
          end
          tl.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_networks:change] Can't get articles", e) and next
      end
    end

    Rails.logger.info "Found #{tl.count} ThoughtLeaders (#{count['count']} expected)"

    puts "\n Please delete all Networks & NetworkTweets from Parse and press Enter !!!"
    STDIN.gets

    tl.each do |t|
      next if t['Networks'].empty?

      # Retrieve all existing networks
      networks = nil

      results = extract_annotations(t['Networks'])

      Retriable.retriable do
        networks = Parse::Query.new('Network').tap do |q|
          q.value_in('NetworkNameLC', results.map{|r| r[:NetworkName].downcase })
        end.get
      end

      t['Networks'] = nil

      # Add relation for existing networks
      networks.each do |n|
        results.delete_if{ |r| r[:NetworkName] == n['NetworkName'] || r[:NetworkName].downcase == n['NetworkName'] }

        t.array_add_relation('Networks', n.pointer)

        # Add Network to fetch information if not fetched yet
        GetNetworkInformation.perform_now(n['objectId']) unless n['InformationFetched']
      end

      # Create missing networks and add relation
      results.each do |r|
        n = Parse::Object.new('Network', {
            NetworkName: r[:NetworkName],
            NetworkNameLC: r[:NetworkName].downcase,
            Industry: r[:Industry],
            Hidden: r[:Hidden],
            identified_by_mention: false,
            mentions: [],
            mentions_count: 0,
            score: 1
        })
        Retriable.retriable do
          n.save
        end

        t.array_add_relation('Networks', n.pointer)

        # Add freshly created Network to fetch images
        GetNetworkInformation.perform_now(n['objectId'], r[:NetworkUrl]) unless r[:Hidden]
      end

      Retriable.retriable do
        t.save
      end
    end

    # Update all articles Networks and NetworkTweets

    Rails.logger.info 'Start updating articles...'

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Article').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next Rails.logger.warn("[update_networks:change] Can't get networks: #{e.message}")
    end

    Rails.logger.info 'No articles to update. Exiting...' and next if !count || count['count'] == 0

    limit = (Rails.env.development? ? 10 : 1000)
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} articles with max #{limit} per page, so looping for #{pages + 1} pages"

    Parallel.each(0..pages, in_threads: 2) do |i|
      begin
        Rails.logger.info "Get articles pages #{i + 1} from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Article').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          ret.each do |a|
            if a['tweets'] && !a['tweets'].empty?
              a['tweets'].each do |tweet|
              networks = nil
              Retriable.retriable do
                networks = Parse::Query.new('Network').tap do |q|
                  q.related_to('Networks', Parse::Pointer.new({'className' => 'ThoughtLeaders', 'objectId' => tweet['user_id']['objectId']}))
                end.get
              end

              if networks && !networks.empty?
                networks.each do |n|
                  # Don't need to check if network already exists, Parse do it for us
                  a.array_add_relation('Networks', n.pointer)

                  # Add related Network to NetworkTweets
                  net = nil
                  Retriable.retriable do
                    net = Parse::Query.new('NetworkTweets').tap do |q|
                      q.eq('Network', n.pointer)
                      q.eq('Article', a.pointer)
                    end.get.first
                  end

                  unless net
                    net = Parse::Object.new('NetworkTweets', {
                        'Network' => n.pointer,
                        'Article' => a.pointer,
                        'tweets' => [],
                        'stats_1h' => 1, 'stats_2h' => 1, 'stats_4h' => 1,
                        'stats_8h' => 1, 'stats_1d' => 1, 'stats_2d' => 1,
                        'stats_3d' => 1, 'stats_1w' => 1, 'stats_2w' => 1,
                        'stats_1m' => 1, 'stats_3m' => 1, 'stats_all' => 1
                    })
                  end

                  if net['tweets'].empty? || net['tweets'].select {|t| t['tweet_id'] == tweet['tweet_id'] || t['user_tweeter_id'] == tweet['user_tweeter_id'] }.empty?
                    # Add tweet to array
                    net['tweets'] << tweet

                    # Update tweets_count
                    net['tweets_count'] = net['tweets'].count
                    net['stats_all'] = net['tweets_count']

                    Retriable.retriable do
                      net.save
                    end
                  end
                end
              end
              end
            end
          end
        end
      rescue Exception => e
        Rails.logger.warn("[update_networks:change] Can't get networks: #{e.message}")
      end
    end

    Rails.logger.info "Updated networks object in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating networks at #{start_time.strftime('%H:%M:%S')}..."

    # Retrieve all existing networks
    networks = nil

    # results = extract_annotations(t['Networks'])

    Retriable.retriable do
      networks = Parse::Query.new('Network').tap do |q|
        q.eq('Hidden', false)
        q.eq('LogoURL', nil)
        q.limit = 1000
      end.get
    end

    networks = extract_annotations(networks)

    networks.each do |n|
      Retriable.retriable do
        n = Parse::Query.new('Network').tap do |q|
          q.eq('Hidden', false)
          q.eq('LogoURL', nil)
          q.limit = 1000
        end.get
      end

      GetNetworkInformation.perform_now(n[:objectId], n[:NetworkUrl])
    end
  end

  task :delete => :environment do
    start_time = Time.now
    Rails.logger.info "Start delete networks at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Network').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_networks:delete] Can't fetch Network", e)
    end

    Rails.logger.info 'No Network to update. Exiting...' and next if !count || count['count'] == 0

    limit = (Rails.env.development? ? 10 : 1000)
    pages = count['count'].fdiv(limit).floor
    networks = []
    Rails.logger.info "Find #{count['count']} Network with max #{limit} per page, so looping for #{pages + 1} pages"

    Parallel.each(0..pages, in_threads: 2) do |i|
      begin
        Rails.logger.info "Get Network from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Network').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          networks.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_networks:delete] Can't get networks", e) and next
      end
    end

    Rails.logger.info "Found #{networks.count} networks (#{count['count']} expected)"

    removed = []

    networks.each do |n|
      next if removed.include?(n['objectId'])

      Network.where(NetworkName: n['NetworkName']).not_eq(id: n['objectId']).map do |s|
        Rails.logger.info "Delete #{s['NetworkName']}..."
        s.destroy
        removed << s.id
      end
    end

    Rails.logger.info "Deleted networks object in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :score => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating networks at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Network').tap do |q|
          q.limit = 0
          q.count
          q.not_eq('rank_fetched', true)
          q.not_eq('NetworkURL', nil)
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_networks:score] Can't get Parse count", e)
    end

    Rails.logger.info 'No networks to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} networks with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get networks from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Network').tap do |q|
            q.limit = limit
            q.skip = limit * i
            q.not_eq('rank_fetched', true)
            q.not_eq('NetworkURL', nil)
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_networks:score] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} networks (#{count['count']} expected)"

    Rails.logger.info 'Loop through all networks and add to job...'

    Parallel.each_with_index(publishers, in_threads: 2) do |p,i|
      prefix = "#{i}/#{publishers.count} >"
      begin
        res = Utils.get_rank(p['NetworkURL'], Rails.logger)

        if res[:rank_fetched]
          p['rank'] = res[:rank]
          p['rank_fetched'] = res[:rank_fetched]
          p['rank_fetched_at'] = res[:rank_fetched_at]

          Retriable.retriable do
            p.save
          end
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_networks:score] #{prefix} Can't fetch publishers: #{p['publication_name']}", e)
      end
    end

    Rails.logger.info "Jobs launched for #{publishers.count} networks in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end

def extract_annotations(results)
  networks = []

  results.map do |r|
    text = r['NetworkName']

    begin
      Retriable.retriable do
        keys = Settings.dandelion.sample
        Dandelionapi.configure do |c|
          c.app_id = keys.app_id
          c.app_key = keys.app_key
          c.endpoint = 'https://api.dandelion.eu/'
        end
        element = Dandelionapi::EntityExtraction.new
        response = element.analyze(text: text, lang: 'en', min_confidence: '0.2', include: 'types,image,lod')
        new_elem = false
        puts "Search: #{text}"
        if response['annotations'] && response['annotations'].is_a?(Array) && response['annotations'].count > 0
          response['annotations'].each do |a|
            if a['types'] && a['types'].is_a?(Array) && a['types'].count > 0
              if a['types'].grep(/^http:\/\/dbpedia.org\/ontology\/(Organisation|Company|Newspaper|Website|Software)/).empty?
                puts "--> Not Found: #{a['label']} and #{a['types'].to_sentence}"
              else
                puts "--> Found: #{a['label']}"
              end
            else
              puts "--> Empty types..."
            end
          end
        else
          puts "--> Not Found: at all"
        end
      end
    rescue Exception => e
      puts "#{e.message}, and #{e}"
      # Rails.logger.warn("Can't find information for AddNetworks #{text}: #{e.message}")
      # ApplicationController.error(@logger, "Can't find information for AddNetworks #{text}", e)
    end
  end

  networks
end
