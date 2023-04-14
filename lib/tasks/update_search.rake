# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_search do
  task :all => :environment do
    # All objects to search

    start_time = Time.now
    Rails.logger.info "Start update_search at #{start_time.strftime('%H:%M:%S')}..."

    add_to_search('Publisher', 'site_name')
    add_to_search('Network', 'NetworkName')
    add_to_search('Industry', 'IndustryName')

    Rails.logger.info "Updated update_search in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end

def add_to_search(main_class, field)
  Rails.logger.info "Updating #{main_class} of field #{field}..."

  count = nil
  begin
    Retriable.retriable do
      count = Parse::Query.new(main_class).tap do |q|
        q.limit = 0
        q.count
      end.get
    end
  rescue Exception => e
    return ApplicationController.error(Rails.logger, "[update_members:count] Can't get Parse count for #{main_class}", e)
  end

  Rails.logger.info "No #{main_class} to update. Exiting..." and return if count['count'] == 0

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
        end.get
        industries.concat ret unless ret.empty?
      end
    rescue Exception => e
      ApplicationController.error(Rails.logger, "[update_members:stats] Can't fetch industries", e)
    end
  end

  Rails.logger.info "Found #{industries.count} objects (#{count['count']} expected)"

  Parallel.each_with_index(industries, in_threads: 1) do |a, i|
    search = nil
    Rails.logger.info "#{i}/#{industries.count} > Updating #{main_class}..."
    begin
      Retriable.retriable do
        search = Parse::Query.new('Search').tap do |q|
          q.eq('EntityType', main_class)
          q.eq('EntityName', a[field])
        end.get.first
      end
    rescue Exception => e
      next ApplicationController.error(Rails.logger, "[update_members:count] Can't get Parse Object", e)
    end

    begin
      data = {
          EntityId: a['objectId'],
          EntityType: main_class,
          EntityName: a[field],
          EntityNameLC: a[field].downcase,
          EntityMedia: a['icon'] || a['IconURL'],
          EntityLogo: a['logo'] || a['LogoURL'],
          EntityColor: a['PrimaryColor'],
          EntityRank: a['rank'],
          EntityHidden: !!a['Hidden'],
          EntityCount: a['ArticlesCount'] || a['MembersCount']
      }

      data[main_class] = a.pointer

      if search
        search.merge! data
      else
        Rails.logger.info "#{i}/#{industries.count} > Object #{main_class} #{a.id} not found in search"
        search = Parse::Object.new('Search', data)
      end

      Retriable.retriable do
        search.save
      end
    rescue Exception => e
      ApplicationController.error(Rails.logger, "[update_members:count] Can't update object #{main_class}##{a['objectId']}", e)
    end
  end
end
