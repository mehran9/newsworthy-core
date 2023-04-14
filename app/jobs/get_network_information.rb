# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class GetNetworkInformation < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger         # Logger for debug / info message
  attr_accessor :object         # Current Network
  attr_accessor :original_logo  # Save logo we found before uploading it to Cloudinary

  def perform(object_id, dbpedia_url = nil, force = false)
    @logger = Delayed::Worker.logger
    @original_logo = nil

    start_time = Time.now

    @logger.info "Start GetNetworkInformation for a Network##{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    @logger.info 'Fetch object from parse...'

    @object = Network.where(id: object_id.to_s).first

    return ApplicationController.error(@logger, "Can't find Network##{object_id}") unless @object

    if force || !@object['NetworkURL']
      # Fetching NetworkURL for the network
      @logger.info "Fetching NetworkURL for network #{@object['NetworkName']}..."
      url = get_domain_url(@object['NetworkName'], dbpedia_url)
      @object['NetworkURL'] = url if url
    end

    ApplicationController.error(@logger, "Can't find url for #{@object['NetworkName']}##{object_id}") and return unless @object['NetworkURL']

    if @object['NetworkURL'] == 'wikipedia.org'
      @logger.info "Hide bad wikipedia.org network #{@object['NetworkName']}..."

      unless @object['Hidden']
        @object.update(Hidden: true)

        # Add hidden true to search
        add_object_to_search(@object)
      end
      return
    end

    if force || !@object['LogoURL']
      # Search for a logo
      @logger.info "Fetching logo for network #{@object['NetworkName']} ('#{@object['NetworkURL']}')..."
      logo = get_image(@object['NetworkURL'], 'logo')
      if logo
        @object['LogoURL'] = logo
      else
        ApplicationController.error(@logger, "Can't find logo for #{@object['NetworkName']}##{object_id}")
      end
    else
      @original_logo = @object['LogoURL']
    end

    if force || !@object['IconURL']
      # Search for a icon
      @logger.info "Fetching icon for network #{@object['NetworkName']} ('#{@object['NetworkURL']}')..."
      icon = get_image(@object['NetworkURL'], 'icon')
      if icon
        @object['IconURL'] = icon
      else
        ApplicationController.error(@logger, "Can't find icon for #{@object['NetworkName']}##{object_id}")
      end
    end

    if @original_logo && (force || !@object['PrimaryColor'])
      # Find dominants colors using original_logo
      @logger.info "Fetching dominants colors for network #{@object['NetworkName']}..."
      colors = get_dominant_colors(@original_logo)

      if colors && colors.is_a?(Array) && colors.count > 0
        @object['PrimaryColor'] = colors.first
        @object['SecondaryColor'] = colors.last if colors.count == 2
      end
    end

    # Check rank
    if @object['NetworkURL'] && (force || !@object['rank_fetched'])
      res = Utils.get_rank(@object['NetworkURL'], @logger)

      @object['rank'] = res[:rank]
      @object['rank_fetched'] = res[:rank_fetched]
      @object['rank_fetched_at'] = res[:rank_fetched_at]
    end

    if @object['InformationFetched']
      @object['MembersCount'] = ThoughtLeaderNetwork.where(relatedId: @object.id.to_s).count
    else
      @object['MembersCount'] = 1
    end

    # True even if we didn't found any information
    @object['InformationFetched'] = true

    @object.save

    # If it's a new Network, add it to Search Class
    add_object_to_search(@object)

    @logger.info "Information found in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def get_image(name, type)
    # For icon, first try using clearbit
    if type == 'icon'
      begin
        url = "https://logo.clearbit.com/#{name}"
        image = upload_image(url, name, 'icon')
        if image # Image uploaded, return url
          @logger.info "Found #{type} using #{url}..."
          return image
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Can't find clearbit #{type} for #{url}", e)
      end

      begin
        url = "https://icons.better-idea.org/icon?url=#{name}&size=120"
        image = upload_image(url, name, 'icon')
        if image # Image uploaded, return url
          @logger.info "Found #{type} using #{url}..."
          return image
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Can't find better-idea #{type} for #{url}", e)
      end
    end

    if @original_logo && type == 'logo'
      image = upload_image(@original_logo, name, type)
      if image # Image uploaded, return url
        @logger.info "Found logo using dbpedia #{@original_logo}..."
        return image
      end
    end

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
                                  search_type: 'image'
        )
      end

      search = nil # memory leak

      image = nil
      if result.items && !result.items.empty?
        # Loop through all images and try upload it
        (type == 'logo' ? result.items.sort{|a,b| (a.image.height / a.image.width) <=> (b.image.height / b.image.width)} : result.items).map do |i|
          image = upload_image(i.link, name, type)
          if image # Image uploaded, return url
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
    # Generate key for Cloudinary
    key = "#{Rails.env}/networks/#{type}/#{Digest::MD5.hexdigest("#{url}#{site_name}")}/#{Digest::MD5.hexdigest(url)}"
    ret = nil
    begin
      # Only trim and make transparent the logo, not the icon
      transformation = []
      if type == 'logo'
        transformation = [
            { effect: 'trim' },              # Trim image
            { effect: 'make_transparent' }   # Make it transparent
        ]
      end

      resp = Cloudinary::Uploader.upload(url,
                                         public_id: key,                                  # unique key
                                         tags: [Rails.env, 'network'],                    # tags for Cloudinary interface
                                         width: (type == 'icon' ? 128 : 750),             # Max width
                                         img_size: (type == 'icon' ? 'small' : 'large'),  # Image size
                                         crop: :limit,                                    # Crop if size limit exceed max width
                                         format: :png,                                    # Convert to png
                                         quality: 80,
                                         transformation: transformation
      )
      # Return url
      ret = resp['url']
    rescue CloudinaryException => e
      @logger.warn("Cloudinary upload_image exception: #{e.message}")
    rescue Exception => e
      @logger.warn("Cant upload logo: #{e.message}")
    end

    ret
  end

  def get_domain_url(query, dbpedia_url)
    if dbpedia_url
      begin
        page = MetaInspector.new(dbpedia_url, { faraday_options: { ssl: false }}).parsed

        # Find the logo using dbpedia
        image = Utils.extract_image_from_dbpedia(@logger, dbpedia_url, page)
        @original_logo = image if image

        @logger.info("Extract root url for #{query} using dbpedia link: #{dbpedia_url}")

        # http://dbpedia.org/page/Siebel_Systems
        # follow dbo:successor
        # successor = page.search("//a[text()='successor']").first
        # if successor
        #   url = r.parent.parent.search('td:nth-child(2) > ul > li:last-child a').first['href']
        #   if url =~ /https?:\/\/[\S]+/
        #     @logger.info("Find successor for #{query}: #{url}")
        #     return get_domain_url(query, url)
        #   end
        # end

        %w(website homepage wikiPageExternalLink).each do |e|
          page.search("//a[text()='#{e}']").each do |r|
            url = r.parent.parent.search('td:nth-child(2) > ul > li:last-child a').text
            if url =~ /https?:\/\/[\S]+/
              url = Utils.get_root_domain(url, @logger)

              return false unless url

              @logger.info("Find url for #{query}: #{url}")
              return url
            end
          end
        end

      rescue Exception => e
        ApplicationController.error(@logger, "Can't extract root url from dbpedia: \"#{dbpedia_url}\"", e)
      end
    end

    begin
      require 'google/apis/customsearch_v1'
      search = Google::Apis::CustomsearchV1::CustomsearchService.new
      search.key = Settings.google.search_api_key
      result = nil

      # Query returns one item only, just the link
      Retriable.retriable do
        result = search.list_cses(query, cx: Settings.google.search_engine_id, fields: 'items/link', num: 1)
      end

      # Return get_root_domain or nil
      (result.items && !result.items.empty? ? Utils.get_root_domain(result.items.first.link, @logger) : nil)
    rescue Exception => e
      ApplicationController.error(@logger, "Can't search for get_domain_url using q: \"#{query}\"", e)
    end
  end

  def get_dominant_colors(url)
    # Generate key for Cloudinary
    key = "#{Rails.env}/dominants/#{Digest::MD5.hexdigest(url)}"
    colors = []
    begin
      resp = Cloudinary::Uploader.upload(url,
                                         public_id: key,                            # unique key
                                         tags: [Rails.env, 'dominants', 'network'], # tags for Cloudinary interface
                                         width: 150                                 # Max width
      )
      return colors unless resp['url']

      agent = Mechanize.new do |agent|
        agent.follow_meta_refresh = true
        agent.keep_alive = false
      end

      tempfile = Tempfile.new('logo_network.png')

      begin
        File.open(tempfile.path, 'wb') do |f|
          f.write agent.get_file(resp['url'])
          f.close
        end
        colors = Miro::DominantColors.new(tempfile.path).to_hex
        @logger.info "Found dominants colors: #{colors}..."
      rescue Exception => e
        @logger.warn("Can't find get_dominant_colors for #{url}: #{e.message}")
        # ApplicationController.error(@logger, "Can't find get_dominant_colors for #{url}", e)
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

  def add_object_to_search(obj)
    @logger.info "Add Network \"#{obj['NetworkName']}\" to Search Class"

    Search.where(EntityType: 'Network', EntityName: obj['NetworkName']).first_or_initialize.update(
        {
            EntityId: obj.id,
            EntityType: 'Network',
            EntityName: obj['NetworkName'],
            EntityNameLC: obj['NetworkName'].downcase,
            EntityMedia: obj['IconURL'],
            EntityLogo: obj['LogoURL'],
            EntityColor: obj['PrimaryColor'],
            EntityHidden: obj['Hidden'],
            EntityCount: obj['MembersCount'],
            Network: obj.pointer
        }
    )
  end
end
