# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_members do
  task :count => :environment do
    # Update object count members

    start_time = Time.now
    Rails.logger.info "Start updating Members count at #{start_time.strftime('%H:%M:%S')}..."

    update_count('Industry', 'ThoughtLeaders', 'Industries', true, 'MembersCount')
    update_count('Network', 'ThoughtLeaders', 'Networks', true, 'MembersCount')
    update_count('Publisher', 'Article', 'site_name', false, 'ArticlesCount')

    Rails.logger.info "Updated members count in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :all => :environment do
    # Update object count members

    start_time = Time.now
    Rails.logger.info "Start updating Members count at #{start_time.strftime('%H:%M:%S')}..."

    update_count('Industry', 'ThoughtLeaders', 'Industries', true, 'MembersCount', false)
    update_count('Network', 'ThoughtLeaders', 'Networks', true, 'MembersCount', false)
    update_count('Publisher', 'Article', 'site_name', false, 'ArticlesCount', false)

    Rails.logger.info "Updated members count in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end

def update_count(main_class, sub_class, related, relationship, field, missing = true)
  Rails.logger.info "Updating #{main_class} with #{sub_class} on field #{field}..."

  count = nil
  begin
    Retriable.retriable do
      count = Parse::Query.new(main_class).tap do |q|
        q.limit = 0
        q.count
        q.eq(field, nil) if missing
      end.get
    end
  rescue Exception => e
    return ApplicationController.error(Rails.logger, "[update_members:count] Can't get Parse count for #{main_class}", e)
  end

  Rails.logger.info "No #{main_class} to update. Exiting..." and return if count['count'] == 0

  # Set query limit to 10 for dev purpose, otherwise to max allowed by parse (1000)
  limit = (Rails.env.development? ? 10 : 1000)

  # Count number of pages to parse
  pages = count['count'].fdiv(limit).floor

  Rails.logger.info "Find #{count['count']} objects with max #{limit} per page, so looping for #{pages + 1} pages"

  # Looping through all pages, one at the time, and fetch all industries using max range limit
  industries = []
  Parallel.each(0..pages, in_threads: 1) do |i| # Change in_threads to make parallel request to parse
    begin
      Rails.logger.info "Get objects from #{i * limit} to #{i * limit + limit - 1}"
      Retriable.retriable do
        ret = Parse::Query.new(main_class).tap do |q|
          q.limit = limit
          q.skip = limit * i
          q.eq(field, nil) if missing
        end.get
        industries.concat ret unless ret.empty?
      end
    rescue Exception => e
      ApplicationController.error(Rails.logger, "[update_members:stats] Can't fetch industries", e)
    end
  end

  Rails.logger.info "Found #{industries.count} objects (#{count['count']} expected)"

  Rails.logger.info 'Loop through all objects and calculate count...'

  Parallel.each_with_index(industries, in_threads: 1) do |a,i|
    count = nil
    begin
      Retriable.retriable do
        count = Parse::Query.new(sub_class).tap do |q|
          if relationship
            q.value_in(related, [a['objectId']])
          else
            q.eq(related, a[related])
          end
          q.limit = 0
          q.count
        end.get
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_members:count] Can't get Parse count: #{main_class}##{a['objectId']}", e)
    end

    begin
      if count && a[field] != count['count']
        Rails.logger.info "#{i}/#{industries.count} . Update count #{count['count']} '#{field}'..."
        a[field] = count['count']
        Retriable.retriable do
          a.save
        end

        search = nil
        Retriable.retriable do
          search = Parse::Query.new('Search').tap do |q|
            q.eq('EntityType', main_class)
            q.eq('EntityId', a['objectId'])
          end.get.first
        end

        if search && search['EntityCount'] != a[field]
          Rails.logger.info "#{i}/#{industries.count} . Update search 'EntityCount'..."
          search['EntityCount'] = a[field]
          Retriable.retriable do
            search.save
          end
        end
      end
    rescue Exception => e
      ApplicationController.error(Rails.logger, "[update_members:count] Can't update object #{main_class}", e)
    end
  end
end
