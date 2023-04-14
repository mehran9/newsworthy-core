# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class GetPublisher < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger
  attr_accessor :original_logo
  attr_accessor :publisher

  def perform(site_name, publication_name, original_icon, article_id, tweet_id, force = false)
    @logger = Delayed::Worker.logger
    @original_logo = nil
    @publisher = nil

    start_time = Time.now

    @logger.info "Start fetching publisher #{site_name} (#{publication_name}) with article #{article_id} at #{start_time.strftime('%H:%M:%S')}..."

    begin
      @publisher = Publisher.where(publication_name: publication_name).first

      # Check rank
      if !@publisher || !@publisher['rank_fetched']
        res = Utils.get_rank(publication_name, @logger)

        rank = res[:rank]
        rank_fetched = res[:rank_fetched]
        rank_fetched_at = res[:rank_fetched_at]
      else
        rank = @publisher['rank']
        rank_fetched = true
        rank_fetched_at = @publisher['rank_fetched_at']
      end

      if rank_fetched && (!rank || rank >= 100000)
        return delete_publisher(publication_name, rank, true)
      end

      if @publisher && @publisher['logo']
        logo = @publisher['logo']
      else
        logo = get_image(site_name, publication_name, 'logo')
      end

      ApplicationController.error(@logger, "Can't find the logo of #{site_name}") unless logo

      if @publisher && @publisher['icon']
        icon = @publisher['icon']
      else
        if original_icon
          @logger.info "Found icon using original #{original_icon}..."
          icon = upload_image(original_icon, site_name, 'icon')
        else
          icon = get_image(site_name, publication_name, 'icon')
        end
      end

      data = {
          'site_name' => site_name.strip,
          'publication_name' => publication_name.strip.gsub('www.', ''),
          'icon' => icon,
          'logo' => (logo ? logo : nil),
          'fetched' => true,
          'found_logo' => !!logo,
          'Hidden' => (@publisher ? @publisher['Hidden'] : false),
          'rank' => rank,
          'rank_fetched' => rank_fetched,
          'rank_fetched_at' => rank_fetched_at
      }

      if !@publisher || !@publisher['PrimaryColor'] || force
        # Find dominants colors using icon or original_logo
        if icon || @original_logo || logo
          @logger.info "Fetching dominants colors for publisher #{site_name}..."
          url = get_good_url(icon, @original_logo, logo)
          if url
            colors = get_dominant_colors(url)

            if colors && colors.is_a?(Array) && colors.count > 0
              data['PrimaryColor'] = colors.first
              data['SecondaryColor'] = colors.last if colors.count == 2
            end
          end
        end
      end

      if @publisher
        data['ArticlesCount'] = get_articles_count(@publisher)
      else
        data['ArticlesCount'] = 1
      end

      if @publisher
        @publisher.update(data)
      else
        if check_if_exists(publication_name)
          @logger.info "Publisher #{site_name} already exists in db, don't create duplicates. Exiting..."
          return
        end
        @publisher = Publisher.create(data)
      end

      # If it's a new Publisher, add it to Search Class
      add_object_to_search(@publisher)

      if article_id && rank
        Utils.update_article_score(article_id, rank)

        if rank <= 5000 || Rails.env.development?
          @logger.info "Fetching entities for publisher #{site_name} (id: #{article_id} rank: #{rank} tweet_id: #{tweet_id})..."
          AddEntities.perform_later(article_id, tweet_id, true, rank)
        end
      end

      @logger.info "Publisher #{site_name}##{@publisher.id} fetched in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
    rescue Exception => e
      ApplicationController.error(@logger, "Can't fetch publisher #{site_name}", e)
    end
  end

  private

  def get_image(site_name, publication_name, type)
    publication_name = Utils.get_root_domain(publication_name, @logger)

    return nil unless publication_name

    # For icon, first try using clearbit
    if type == 'icon'
      begin
        url = "https://logo.clearbit.com/#{publication_name}"
        image = upload_image(url, publication_name, 'icon')
        if image # Image uploaded, return url
          @logger.info "Found icon using #{url}..."
          return image
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Can't find clearbit #{type} for #{url}", e)
      end

      begin
        url = "https://icons.better-idea.org/icon?url=#{publication_name}&size=120"
        image = upload_image(url, publication_name, 'icon')
        if image # Image uploaded, return url
          @logger.info "Found icon using #{url}..."
          return image
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Can't find better-idea #{type} for #{url}", e)
      end
    end

    begin
      require 'google/apis/customsearch_v1'
      search = Google::Apis::CustomsearchV1::CustomsearchService.new
      search.key = Settings.google.search_api_key
      result = nil
      image = nil
      query = "#{site_name} #{type}"

      @logger.info "Query google image with #{query}..."

      Retriable.retriable do
        result = search.list_cses(query,
                                  cx: Settings.google.search_engine_id,
                                  fields: 'items/link,items/image/height,items/image/width',
                                  num: 10,
                                  search_type: 'image'
        )
      end

      search = nil # memory leak

      if result.items && !result.items.empty?
        # Loop through all images and try upload it
        (type == 'logo' ? result.items.sort{|a,b| (a.image.height / a.image.width) <=> (b.image.height / b.image.width)} : result.items).map do |i|
          image = upload_image(i.link, publication_name, type)
          if image # Image uploaded, return url
            @logger.info "Found #{type} using #{i.link}..."
            @original_logo = i.link if type == 'logo'
            break
          end
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
    key = "#{Rails.env}/publisher/#{type}/#{Digest::MD5.hexdigest("#{url}#{site_name}")}/#{Digest::MD5.hexdigest(url)}"
    logo = nil

    begin
      transformation = []
      if type == 'logo'
        transformation = [
            { effect: 'trim' },
            { effect: 'make_transparent' }
        ]
      end
      resp = Cloudinary::Uploader.upload(url,
                                         public_id: key,
                                         tags: [Rails.env, 'publisher'],
                                         width: 750,
                                         crop: :limit,
                                         format: :png,
                                         quality: 80,
                                         transformation: transformation
      )
      logo = resp['url']
    rescue CloudinaryException => e
      @logger.warn("Cloudinary upload_image exception for #{url}: #{e.message}")
    rescue Exception => e
      @logger.warn("Cant upload image for #{url}: #{e.message}")
    end
    logo
  end

  def add_object_to_search(obj)
    @logger.info "Add Publisher \"#{obj['site_name']}\" to Search Class"

    Search.where(EntityType: 'Publisher', EntityName: obj['site_name']).first_or_initialize.update({
        EntityId: obj.id,
        EntityType: 'Publisher',
        EntityName: obj['site_name'],
        EntityNameLC: obj['site_name'].downcase,
        EntityMedia: obj['icon'],
        EntityLogo: obj['logo'],
        EntityColor: obj['PrimaryColor'],
        EntityRank: obj['rank'],
        EntityHidden: obj['Hidden'],
        EntityCount: obj['ArticlesCount'],
        Publisher: obj.pointer
    })
  end

  def get_good_url(icon, o_logo, logo)
    [o_logo, logo, icon].each do |t|
      if t
        m = t.match('\.([A-Za-z0-9]+)$')
        if m && m[1] && m[1] != 'ico'
          return t
        end
      end
    end
    nil
  end

  def get_dominant_colors(url)
    colors = []

    # Generate key for Cloudinary
    key = "#{Rails.env}/dominants/#{Digest::MD5.hexdigest(url)}"

    begin
      resp = Cloudinary::Uploader.upload(url,
                                         public_id: key,                              # unique key
                                         tags: [Rails.env, 'dominants', 'publisher'], # tags for Cloudinary interface
                                         width: 150                                   # Max width
      )
      return colors unless resp['url']

      agent = Mechanize.new do |agent|
        agent.follow_meta_refresh = true
        agent.keep_alive = false
      end

      tempfile = Tempfile.new('logo_publisher.png')

      begin
        File.open(tempfile.path, 'wb') do |f|
          f.write agent.get_file(resp['url'])
          f.close
        end
        colors = Miro::DominantColors.new(tempfile.path).to_hex
      rescue Exception => e
        # @logger.warn("Can't find get_dominant_colors: #{e.message}")
        ApplicationController.error(@logger, "Can't find get_dominant_colors for #{url}", e)
      end

      DeleteImage.perform_later(key)
      tempfile.unlink

    rescue CloudinaryException => e
      @logger.warn("Cloudinary get_dominant_colors exception: #{e.message}")
    rescue Exception => e
      @logger.warn("Can't upload get_dominant_colors: #{e.message}")
    end

    # Returns colors
    colors
  end

  def get_articles_count(obj)
    Article.where(publication_name: obj['publication_name']).count
  end

  def delete_publisher(publication_name, rank = nil, banned = false)
    if @publisher
      @logger.info "Hide old publisher: #{publication_name}"
      @publisher.update(Hidden: true)

      search = Search.where(EntityType: 'Publisher', EntityName: @publisher['site_name']).first

      if search
        @logger.info "Hide old search: #{publication_name}"
        search.update(EntityHidden: true)
      end
    end

    if banned
      @logger.info "Add banned publisher: #{publication_name}"

      unless BannedPublication.where(name: publication_name).exists?
        BannedPublication.create(name: publication_name, rank: rank, rank_fetched: true)
      end

      Article.where(publication_name: publication_name).destroy_all
    end
  end

  def check_if_exists(publication_name)
    Publisher.where(publication_name: publication_name).exists?
  end
end
