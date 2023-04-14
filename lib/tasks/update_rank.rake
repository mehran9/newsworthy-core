# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :update_rank do
  task :all => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating rank at #{start_time.strftime('%H:%M:%S')}..."

    Parallel.each(%w(Publisher Network), in_threads: 2) do |main_class|
      update_rank(main_class)
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :first_time => :environment do
    start_time = Time.now
    Rails.logger.info "Start updating rank at #{start_time.strftime('%H:%M:%S')}..."

    Parallel.each(%w(Publisher), in_threads: 2) do |main_class|
      update_rank(main_class, true)
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def update_rank(main_class, first = false)
    start_time = Time.now
    Rails.logger.info "-> Start updating #{main_class} rank at #{start_time.strftime('%H:%M:%S')}..."

    where = {}
    where[:rank_fetched_at] = 1.month.ago unless first
    where[:Hidden] = true unless main_class == 'Publisher'

    only = main_class == 'Publisher' ? :publication_name : :NetworkURL

    objects = class_eval(main_class).only(only, :Hidden, :rank, :rank_fetched_at).where(where).to_a

    Rails.logger.info "Found #{objects.count} #{main_class}"

    Rails.logger.info "Loop through all #{main_class}..."

    deleted_objects = []
    unban_objects = []
    elem = 0
    Parallel.each_with_index(objects, in_threads: 2) do |o,i|
      prefix = "#{i}/#{objects.count} >"
      begin
        elem += 1
        res = nil
        url = o['publication_name'] || o['NetworkURL']
        Retriable.retriable do
          res = Amazon::Awis.get_info(url)
        end
        if res && res.success?
          obj = {}
          if res.get_all('Country').count > 0
            rank = res.get_all('Country').select{|e| !e.rank.first.to_s.empty? }.sort_by{|e| e.rank.first.to_s.to_i }.first.rank.first.to_s.to_i
            if main_class == 'Publisher'
              if !o['Hidden'] && (!rank || rank >= 100000)
                obj['Hidden'] = true
                deleted_objects << o
              elsif o['Hidden'] && rank && rank < 100000
                obj['Hidden'] = false
                unban_objects << o
              end
            end
            obj['rank'] = rank
          end
          obj['rank_fetched_at'] = Time.now
          class_eval(main_class).where(id: o.id).update(obj) # Documents loaded from the database using #only cannot be persisted
        end
      rescue Exception => e
        ApplicationController.error(Rails.logger, "[update_rank:all] #{prefix} Can't fetch #{main_class}: #{url}", e)
      end
    end

    if deleted_objects.count > 0
      Rails.logger.info "Found #{deleted_objects.count} publishers to delete"
      deleted_objects.map do |p| # One at the time, Concurrency Issue
        delete_publisher(p)
      end
    end

    if unban_objects.count > 0
      Rails.logger.info "Found #{unban_objects.count} publishers to activate"
      unban_objects.map do |p| # One at the time, Concurrency Issue
        activate_publisher(p)
      end
    end

    Rails.logger.info "-> Updated rank #{main_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  def delete_publisher(publisher)
    search = Search.where(EntityType: 'Publisher', EntityId: publisher.id).first

    if search
      Rails.logger.info "   Hide old search: #{publisher['publication_name']}"
      search.update(EntityHidden: true)
    end

    unless BannedPublication.where(name: publisher['publication_name']).exists?
      BannedPublication.create(name: publisher['publication_name'], rank: publisher['rank'], rank_fetched: true)
    end

    Article.where(publication_name: publisher['publication_name']).destroy_all
  end

  def activate_publisher(publisher)
    search = Search.where(EntityType: 'Publisher', EntityId: publisher.id).first

    if search
      Rails.logger.info "   Unhide old search: #{publisher['publication_name']}"
      search.update(EntityHidden: false)
    end

    BannedPublication.where(name: publisher['publication_name']).map do |p|
      Rails.logger.info "   Unban publisher: #{publisher['publication_name']}"
      p.destroy
    end
  end
end
