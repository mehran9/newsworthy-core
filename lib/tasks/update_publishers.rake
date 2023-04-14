# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_publishers do
  task :colors => :environment do
    # Update industries count stats

    start_time = Time.now
    Rails.logger.info "Start updating publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Publisher').tap do |q|
          q.eq('PrimaryColor', nil)
          q.eq('fetched', true)
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:colors] Can't get Parse count", e)
    end

    Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Publisher').tap do |q|
            q.eq('PrimaryColor', nil)
            q.eq('fetched', true)
            q.limit = limit
            q.skip = limit * i
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:colors] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} publishers (#{count['count']} expected)"

    Rails.logger.info 'Loop through all publishers and add to job...'

    publishers.each do |p|
      GetPublisher.perform_later(p['site_name'], p['icon'])
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :dandelion => :environment do
    # Update industries count stats

    start_time = Time.now
    Rails.logger.info "Start updating publishers at #{start_time.strftime('%H:%M:%S')}..."
    #
    # count = nil
    # begin
    #   Retriable.retriable do
    #     count = Parse::Query.new('Publisher').tap do |q|
    #       q.limit = 0
    #       q.count
    #     end.get
    #   end
    # rescue Exception => e
    #   next ApplicationController.error(Rails.logger, "[update_publishers:dandelion] Can't get Parse count", e)
    # end
    #
    # Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0
    #
    # # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    # limit = (Rails.env.development? ? 10 : 1000)
    #
    # # Count number of pages to parse
    # pages = count['count'].fdiv(limit).floor
    #
    # Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    # Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
    #   begin
    #     Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
    #     Retriable.retriable do
    #       ret = Parse::Query.new('Publisher').tap do |q|
    #         q.limit = limit
    #         q.skip = limit * i
    #       end.get
    #       publishers.concat ret unless ret.empty?
    #     end
    #   rescue Exception => e
    #     ApplicationController.error(Rails.logger, "[update_publishers:dandelion] Can't fetch publishers", e)
    #   end
    # end

    publishers = Parse::Query.new('Publisher').tap do |q|
      q.limit = 1000
      q.eq('publication_name', nil)
      q.order_by = 'updatedAt'
    end.get

    Rails.logger.info "Found #{publishers.count} publishers"

    Rails.logger.info 'Loop through all publishers and add to job...'

    publishers.each do |p|
      GetPublisher.perform_later(p['site_name'], '', p['icon'], false, true)
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :add_www => :environment do
    # Update industries count stats

    start_time = Time.now
    Rails.logger.info "Start updating publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Publisher').tap do |q|
          q.eq('publication_name', nil)
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:add_www] Can't get Parse count", e)
    end

    Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Publisher').tap do |q|
            q.eq('publication_name', nil)
            q.limit = limit
            q.skip = limit * i
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:add_www] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} publishers (#{count['count']} expected)"

    Rails.logger.info 'Loop through all publishers and add to job...'

    Parallel.each(publishers, in_threads: 2) do |p|
      article = nil
      Retriable.retriable do
        article = Parse::Query.new('Article').tap do |q|
          q.eq('site_name', p['site_name'])
        end.get.first
      end

      if article
        Rails.logger.info "Article found: #{article['publication_name']}"
        p['publication_name'] = article['publication_name']
        Retriable.retriable do
          p.save
        end
      end
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :score => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Publisher').tap do |q|
          q.limit = 0
          q.count
          q.not_eq('rank_fetched', true)
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:score] Can't get Parse count", e)
    end

    Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Publisher').tap do |q|
            q.limit = limit
            q.skip = limit * i
            q.not_eq('rank_fetched', true)
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:score] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} publishers (#{count['count']} expected)"

    Rails.logger.info 'Loop through all publishers and add to job...'

    Parallel.each_with_index(publishers, in_threads: 2) do |p,i|
      count = nil
      prefix = "#{i}/#{publishers.count} >"
      begin
        count = Publisher.where(publication_name: p['publication_name']).count

        next if count <= 0

        if count > 1
          Rails.logger.info "#{prefix} Publication duplicated: #{p['publication_name']}"
          Publisher.where(id: p.id).destroy_all
        else
          res = Utils.get_rank(p['publication_name'], Rails.logger)

          if res[:rank_fetched]
            Publisher.where(id: p.id).first.update(res)
          end
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:score] #{prefix} Can't fetch publishers: #{p['publication_name']}", e)
      end
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :missing => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Article').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:missing] Can't get Parse count", e)
    end

    Rails.logger.info 'No Article to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    last_created_at = nil
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Article').tap do |q|
            q.limit = limit
            q.skip = limit * i
            q.order_by('createdAt')
            # q.greater_than('createdAt', last_created_at) if last_created_at
          end.get
          publishers.concat ret unless ret.empty?
          # last_created_at = ret.last['createdAt']
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:score] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} publishers (#{count['count']} expected)"

    Rails.logger.info 'Loop through all publishers and add to job...'

    Parallel.each_with_index(publishers, in_threads: 2) do |p,i|
      count = nil
      prefix = "#{i}/#{publishers.count} >"
      begin
        Retriable.retriable do
          count = Parse::Query.new('Publisher').tap do |q|
            q.eq('publication_name', p['publication_name'])
          end.get.count
        end

        if count <= 0
          Rails.logger.info "#{i}/#{publishers.count} > Missing publisher #{p['publication_name']}"
          GetPublisher.perform_later(p['site_name'], p['publication_name'])
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:score] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating all publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Publisher').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:update] Can't get Parse count", e)
    end

    Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Publisher').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          publishers.concat ret unless ret.empty?
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:score] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} publishers (#{count['count']} expected)"

    Rails.logger.info 'Loop through all publishers and add to job...'

    publishers.each do |p|
      GetPublisher.perform_later(p['site_name'], p['publication_name'], false, false, true)
    end

    Rails.logger.info "Jobs launched for #{publishers.count} publishers in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_banned => :environment do
    start_time = Time.now
    Rails.logger.info "Start update banned publisher at #{start_time.strftime('%H:%M:%S')}..."

    publishers = BannedPublication.only(:name).where(:_created_at.gte => 1.hour.ago).to_a

    Rails.logger.info "Found #{publishers.count} BannedPublication"

    Parallel.each_with_index(publishers) do |p,i|
      prefix = "#{i}/#{publishers.count} >"
      begin
        Publisher.where(publication_name: p['name'], :Hidden.ne => false).map do |pu|
          Rails.logger.info "#{prefix} Hide publication: #{p['name']}"
          pu.update(Hidden: true)

          Search.where(EntityId: pu.id, EntityType: 'Publisher', :Hidden.ne => false).map do |s|
            Rails.logger.info "#{prefix} Hide search: #{s['EntityName']}"
            s.update(Hidden: true)
          end
        end

        Article.where(publication_name: p['name']).destroy_all
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:update_banned] #{prefix} Can't fetch BannedPublication: #{p['name']}", e)
      end
    end

    Rails.logger.info "Update for #{publishers.count} BannedPublication in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :update_banned_all => :environment do
    start_time = Time.now
    Rails.logger.info "Start update all banned publisher at #{start_time.strftime('%H:%M:%S')}..."

    publishers = BannedPublication.only(:name).to_a

    Rails.logger.info "Found #{publishers.count} BannedPublication"

    Parallel.each_with_index(publishers) do |p,i|
      prefix = "#{i}/#{publishers.count} >"
      begin
        Publisher.where(publication_name: p['name'], :Hidden.ne => false).map do |pu|
          Rails.logger.info "#{prefix} Hide publication: #{p['name']}"
          pu.update(Hidden: true)

          Search.where(EntityId: pu.id, EntityType: 'Publisher', :Hidden.ne => false).map do |s|
            Rails.logger.info "#{prefix} Hide search: #{s['EntityName']}"
            s.update(Hidden: true)
          end
        end

        Article.where(publication_name: p['name']).destroy_all
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:update_banned] #{prefix} Can't fetch BannedPublication: #{p['name']}", e)
      end
    end

    Rails.logger.info "Update for #{publishers.count} BannedPublication in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :duplicates => :environment do
    start_time = Time.now
    Rails.logger.info "Start remove duplicates publishers at #{start_time.strftime('%H:%M:%S')}..."

    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new('Publisher').tap do |q|
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_publishers:duplicates] Can't get Parse count", e)
    end

    Rails.logger.info 'No publishers to update. Exiting...' and exit(0) if count['count'] == 0

    # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
    limit = (Rails.env.development? ? 10 : 1000)

    # Count number of pages to parse
    pages = count['count'].fdiv(limit).floor

    Rails.logger.info "Find #{count['count']} publishers with max #{limit} per page, so looping for #{pages + 1} pages"

    # Looping through all pages, one at the time, and fetch all publishers using max range limit
    publishers = []
    domains_names = []
    Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
      begin
        Rails.logger.info "Get publishers from #{i * limit} to #{i * limit + limit - 1}"
        Retriable.retriable do
          ret = Parse::Query.new('Publisher').tap do |q|
            q.limit = limit
            q.skip = limit * i
          end.get
          unless ret.empty?
            ret.map do |p|
              if p['publication_name']
                if domains_names.include?(p['publication_name'])
                  publishers << p
                else
                  domains_names << p['publication_name']
                end
              else
                Rails.logger.info "Empty publication name for #{p['site_name']}"
              end
            end
          end
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_publishers:duplicates] Can't fetch publishers", e)
      end
    end

    Rails.logger.info "Found #{publishers.count} duplicates (#{count['count']} total publishers)"

    publishers.each do |p|
      Rails.logger.info "Searching for all publishers with domain #{p['publication_name']}..."

      pub = nil
      Retriable.retriable do
        pub = Parse::Query.new('Publisher').tap do |q|
          q.eq('publication_name', p['publication_name'])
          q.order_by = 'ArticlesCount'
          q.order = :descending
        end.get
      end

      count = 0
      pub.map{|m| count += m['ArticlesCount']}

      Rails.logger.info "We will use #{pub.first['site_name']} (#{pub.first['publication_name']}) as default with count #{count}"

      pub.each_with_index do |d_p, index|
        if index == 0
          Rails.logger.info "Keep first publisher #{d_p['site_name']} (#{d_p['publication_name']}) and update ArticlesCount..."
          d_p['ArticlesCount'] = count
          Retriable.retriable do
            d_p.save
          end

          search = nil
          Retriable.retriable do
            search = Parse::Query.new('Search').tap do |q|
              q.eq('Publisher', d_p.pointer)
            end.get.first
          end
          if search
            search['EntityCount'] = count
            Retriable.retriable do
              search.save
            end
          else
            Rails.logger.info "What? no search for Publisher #{d_p.id}"
          end
        else
          Rails.logger.info "Searching for articles with #{d_p['site_name']} (#{d_p['publication_name']})..."
          articles = nil
          Retriable.retriable do
            articles = Parse::Query.new('Article').tap do |q|
              q.eq('site_name', d_p['site_name'])
            end.get
          end

          articles.map do |a|
            Rails.logger.info "Saving article #{a.id} with new data..."
            a['site_name'] = pub.first['site_name']
            a['publication_name'] = pub.first['publication_name']
            Retriable.retriable do
              a.save
            end
          end

          Publisher.where(id: d_p.id).destroy_all
        end
      end
    end

    Rails.logger.info "#{publishers.count} duplicates deleted in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
