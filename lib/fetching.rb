# -*- encoding : utf-8 -*-
# noinspection RubyStringKeysInHashInspection

module Fetching
  class Content
    attr_accessor :logger
    attr_accessor :article
    attr_accessor :tweet
    attr_accessor :topic
    attr_accessor :retries
    attr_accessor :diffbot_issue
    attr_accessor :diffbot_cache
    attr_accessor :data
    attr_accessor :merged

    def initialize(opts = {})
      @logger = opts[:logger] || Logger.new(STDOUT).tap{|l|
        l.level = "Logger::#{Rails.application.config.log_level.to_s.upcase}".constantize
      }
      @retries = opts[:retries] || 0
      @article = opts[:article]
      @tweet = opts[:tweet]
      @topic = opts[:topic]
      @diffbot_issue = opts[:diffbot_issue]
      @diffbot_cache = nil
      @data = {}
      @merged = false
    end

    def get_url(url)
      begin
        if url =~ /:\/\/linkis.com\// || url =~ /:\/\/ln.is\//
          expanded_url = get_linkis_url(url)
          return false unless expanded_url
          url = expanded_url
        end

        root_url = Utils.get_root_domain(url, @logger)
        return false unless root_url

        if banned_publication?(root_url)
          @logger.info "Publication #{root_url} is banned. Skipping..."
          return false
        end

        if banned_extension?(url)
          @logger.info "Invalid extension for url #{url}. Skipping..."
          return false
        end

        if invalid_content?(url)
          @logger.info "Page content length for #{url} is invalid. Skipping..."
          return false
        end

        info = fetch_from_diffbot(url)

        return false unless info

        url = get_resolved_url(url, info)
        url_2 = get_clean_url(url)

        if banned_publication?(url_2.host)
          @logger.info "Publication #{url_2.host} is banned. Skipping..."
          return false
        end

        if banned_extension?(url_2)
          @logger.info "Invalid extension for url #{url_2}. Skipping..."
          return false
        end

        @diffbot_cache = info['objects'].first

        return url_2.to_s if url == url_2.to_s

        info_2 = fetch_from_diffbot(url_2.to_s)

        if info_2
          if info['objects'].first['text'] == info_2['objects'].first['text']
            return url_2.to_s
          end

          require 'fuzzystringmatch'
          jarow = FuzzyStringMatch::JaroWinkler.create(:native)
          percent = jarow.getDistance(info['objects'].first['text'], info_2['objects'].first['text'])

          if percent >= 0.8
            return url_2.to_s
          else
            if @diffbot_issue
              @logger.warn("Content matching issue #2 for #{url}")
              return url
            else
              # ApplicationController.error(@logger, "Content matching issue for #{url}")
              FetchArticle.set(wait: 3.minutes).perform_later(@tweet, @topic, url, @retries, true)
              return false
            end
          end
        else
          return false
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Can't lengthen url #{url}", e)
        return false
      end
    end

    def get_content(url, quick = false)
      begin
        Retriable.retriable do
          ret = get_diffbot_data(url)
          if ret
            return ret if ret.class == Article # found a duplicate article using md5 content
            @data.merge!(ret)
          else
            return false
          end

          unless @article || quick
            ret = get_meaning_cloud_data(url)
            if ret
              @data.merge!(ret)
            else
              return false
            end
          end

          get_images_data(quick)

          unless @merged || quick
            state = search_duplicates(url, @data['md5_content'])
            return state if state
          end
        end
        return @data
      rescue Exception => e
        return ApplicationController.error(@logger, "Fail retry fetch_content for #{url}", e)
      end
    end

    private

    def get_linkis_url(url)
      begin
        page = MetaInspector.new(url, { faraday_options: { ssl: false }})
        if page.response.status == 200
          html_doc = Nokogiri::HTML(page.to_s)

          %w(js-source-link js-original-link).each do |link|
            html_doc.xpath("//a[contains(@class, \"#{link}\")]").each do |elem|
              if elem && elem.text =~ /^http/
                return (elem.text =~ /^https?:\/\// ? elem.text : "http://#{elem.text}")
              end
            end
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

    def get_resolved_url(url, info)
      if info['request']['resolvedPageUrl']
        url = info['request']['resolvedPageUrl']
      elsif info['objects'].first['resolvedPageUrl']
        url = info['objects'].first['resolvedPageUrl']
      end
      get_clean_url(url, true).to_s
    end

    def get_clean_url(url, remove_params = false)
      require 'addressable/uri'
      uri = Addressable::URI.parse(url)
      uri.normalize
      uri.host = uri.host.gsub(/^mobile\./i, 'www.')
      uri.fragment = nil
      uri.scheme = 'http'
      uri.path.gsub!(/\/comments\/$/, '') # Remove the /comments/ at the end of the url
      if remove_params && uri.query
        params = {}
        ignore = %w(_r mtrref gwh gwt utm_.* ut_.* um_.* pk_.* rss smid smtyp inf_contact_key _ga awesm sf cm_.* linkid _hs.* xid partner wpmm wpisrc hootpostid share mod ncid s_cid mc_.* mkt_tok crlt\..* _lrsc social_token fb_ref bt_alias sr_share fsrc referer spmailingid srid cmp recruiter midtoken wt\..* ref campaign_.* dm1_.* trk _i_location)
        URI.decode_www_form(uri.query).each do |k, v|
          params[k] = v if !v.empty? && ignore.select {|i| k.match("^#{i}$") }.empty?
        end
        uri.query = (params.empty? ? nil : URI.encode_www_form(params))
      else
        uri.query = nil
      end
      uri
    end

    def fetch_from_diffbot(url)
      info = nil
      begin
        Retriable.retriable do
          info = Biffbot::Analyze.new(url)
        end
      rescue Exception => e
        unless @article
          if @retries < 3
            FetchArticle.set(wait: (@retries + 1).hours).perform_later(@tweet, @topic, url, @retries + 1)
          else
            ApplicationController.error(@logger, "Diffbot fetch_from_diffbot for #{url} with retry #{@retries}", e)
          end
        end
        return false
      end

      if info['errorCode']
        if info['errorCode'] == 500 && !@article
          if info['error'].match(/\(\d+\)/)
            error_code = info['error'].match(/\(\d+\)/)[0]
          else
            error_code = 999
          end
          # igonred_errors = ['Empty content', 'Could not download page (415)', 'Could not download page (999)', 'Could not download page (416)', 'Could not download page (403)']
          if error_code == 500
            if @retries < 3
              FetchArticle.set(wait: (@retries + 1).hours).perform_later(@tweet, @topic, url, @retries + 1)
            else
              ApplicationController.error(@logger, "Diffbot API outage: #{info['error']} for #{url} with retry #{@retries}")
            end
          end
        elsif info['errorCode'] == 429 || info['errorCode'] == 401
          ApplicationController.error(@logger, "Diffbot API problem: #{info['error']}")
        end
        return false
      end

      if info['errorCode'] || info['type'] != 'article' || !info['objects'] || info['objects'].count != 1
        @logger.info 'Not an article. Skipping...'
        false
      else
        info
      end
    end

    def get_diffbot_data(url)
      if @diffbot_cache
        obj = @diffbot_cache
        @diffbot_cache = nil #memory leak
      else
        info = fetch_from_diffbot(url)
        return false unless info
        obj = info['objects'].first
      end

      content = get_article_content(obj)

      # Strange NoMethodError: undefined method `empty?' for nil:NilClass ...
      begin
        if !content || content.empty? || !obj['title'] || obj['title'].empty?
          @logger.info 'No diffbot html / text or title'
          return false
        end
      rescue Exception => e
        return false
      end

      # If text is empty but html don't, extract text from html
      if !obj['text'] || obj['text'].empty?
        tmp = Nokogiri::HTML(obj['html'])
        obj['text'] = tmp.search('body').children.text.strip
      end

      md5_content = Digest::MD5.hexdigest(content)

      state = search_duplicates(url, md5_content)
      return state if state
      
      ret = {
          'url'               => url,
          'title'             => obj['title'].strip,
          'publication_name'  => URI(url).host.gsub('www.', ''),
          'site_name'         => (obj['siteName'] ? obj['siteName'].strip : URI(url).host.gsub('www.', '')),
          'author'            => (obj['author'] ? obj['author'].gsub(/\\/, '').strip : nil),
          'language'          => (obj['humanLanguage'] ? obj['humanLanguage'].strip : nil),
          'content'           => content,
          'images'            => get_images_array(obj['images'], content),
          'md5_content'       => md5_content,
          'text'              => obj['text'].strip,
          'webviewonly'       => !(obj['text'] && obj['text'].size >= 100),
          'icon'              => obj['icon'],
          'videos'            => get_videos_array(obj['videos'])
      }
      if @article
        ret['published_at'] = ret['published_at'] ? ret['published_at'] : Time.now.utc.iso8601(3).to_time
      else
        ret['published_at'] = get_article_date(url, obj)
      end
      ret
    end

    def search_duplicates(url, md5_content)
      articles = Article.or({md5_content: md5_content}, {url: url}).order(tweets_count: 'desc')

      if @article
        articles = articles.select{|a| a.id != @article.id }
      end

      # If empty, no duplicates found
      return false if articles.empty?

      # If UpdateArticle job
      if @article
        @logger.info "Found duplicates on update for article #{@article.id}, use #{articles.first.id}"

        # Cue a MergeArticles job with this md5 and url, in 30s to be sure the article will be updated at this time
        MergeArticles.set(wait: 30.seconds).perform_later(md5_content, url, articles.first.class.to_s)

        # Flag that we already found duplicates
        @merged = true
        false
      else
        article = articles.first
        @logger.info "Found duplicates on creation for article, use #{article.id}"
        if url.size < article['url'].size
          @logger.info "New url is smaller, save url #{url} for article #{article.id}"
          article['url'] = url
          article.save
        end
        article
      end
    end

    def get_meaning_cloud_data(url)
      if @data['language'].present?
        model = "IPTC_#{@data['language']}"
      else
        model = 'IPTC_en'
      end

      info = nil
      begin
        Retriable.retriable do
          info = MeaningCloud::TextClassification.extract(title: @data['title'], txt: @data['text'], model: model)
        end
      rescue Exception => e
        @logger.warn "Fail retry fetch_content MeaningCloud #{url} with retry #{@retries}: #{e.class}: '#{e.message}"
        return false
      end

      if info && info['status']['msg'] == 'OK'
        categories = []
        sub_categories = []

        info['category_list'].map do |c|
          cat = Settings.categories[c['code'][0..1].to_sym]
          sub_cat = Settings.categories[c['code'][0..4].to_sym]
          categories << cat if cat && !categories.include?(cat)
          sub_categories << sub_cat if sub_cat && !categories.include?(sub_cat)
        end

        { Categories: categories, SubCategories: sub_categories }
      else
        # @logger.info "No meaning_cloud data for #{url}"
        unless info['status']['msg'] == 'OK'
          @logger.warn "No meaning_cloud data for #{url}: Status: #{info['status']['msg']} Credit: #{info['status']['remaining_credits']}"
          # ApplicationController.error(@logger, "No meaning_cloud data for #{url}: Status: #{info['status']['msg']} Credit: #{info['status']['remaining_credits']}")
        end
        {}
      end
    end

    def get_article_date(url, obj)
      date = nil
      keys = { 'name' => %w(DC.date.issued pubdate date search_date article.published), 'property' => ['article:published_time'] }
      begin
        page = MetaInspector.new(url, { faraday_options: { ssl: false }})
        if page.response.status == 200
          catch :done do
            keys.each do |k,v|
              v.each do |e|
                if page.meta_tags[k] && page.meta_tags[k][e] && !page.meta_tags[k][e].first.empty?
                  date = page.meta_tags[k][e].first
                  throw :done
                end
              end
            end
          end
        end

      rescue Exception => e
        @logger.warn("Fail retry get_article_date #{url} - #{e.class}: '#{e.message}")
      end

      begin
        unless date
          if obj['date'] && !obj['date'].empty?
            date = obj['date']
          elsif obj['estimatedDate'] && !obj['estimatedDate'].empty?
            date = obj['estimatedDate']
          end
        end
      rescue Exception => e
        # ignored
      end
      (date ? Time.parse(date) : Time.now.utc.iso8601(3)).to_time
    end

    def get_article_content(obj)
      return obj['text'] unless obj['html']

      html_doc = Nokogiri::HTML(obj['html'])

      # Return html when body is missing
      unless html_doc.at('body')
        return obj['html']
      end

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

      if images.count < 1
        html = html_doc.search('body').children.to_html
        return html
      end

      elem = images.first
      count = 0
      html_doc.at_css('body').traverse do |e|
        next if e.name == 'text'
        break if e.object_id == elem.object_id
        count += e.text.size if e.text.size > 2
        break if count > 200
      end

      if count <= 200
        elem = find_image_element(elem, true)
        elem.remove
      end

      html_doc.search('body').children.to_html.gsub(/^\n/,'')
    end

    def get_images_array(images, content)
      ret = []
      if images
        ret = images.select do |i|
          i['url'] && !i['url'].empty?
        end.collect do |i|
          # { 'url' => URI::encode(i['url']), 'key' => nil, 'width' => i['width'] || nil }
          { 'url' => i['url'], 'key' => nil, 'width' => get_image_width(i) }
        end
      end

      html_doc = Nokogiri::HTML(content)
      html_doc.search('img').each do |i|
        if i['src'] && ret.select{ |s| s['url'] == i['src'] }.empty?
          # ret << { 'url' => URI::encode(i['src']), 'key' => nil, 'width' => nil }
          ret << { 'url' => i['src'], 'key' => nil, 'width' => nil }
        end
      end
      ret
    end

    def get_videos_array(videos)
      videos ? videos.select { |i| !i['url'].empty? }.collect { |i| URI::encode(i['url']) } : []
    end

    def get_image_width(image)
      width = nil
      %w(naturalWidth width pixelWidth).each do |w|
        if image[w] && image[w] != 0
          width = image[w]
          break
        end
      end
      width
    end

    def get_images_data(quick, second_pass = false)
      images = []
      removed_images = []
      images_keys = []

      # Remove existing images from diffbot returns
      if @article && !second_pass && !@article['images'].empty?
        @article['images'].each do |i|
          img_old = nil
          if i['url'] =~ /^http:\/\/res.cloudinary.com\/newsworthy/
            @data['images'].delete_if{|d| img_old = d if get_image_key(@article, d['url']) == i['key']}
          else
            @data['images'].delete_if{|d| img_old = d if d['url'] == i['url'] }
          end
          images << i if img_old
        end
      end

      @data['images'].each do |i|
        if i['width'] && i['width'] < 300
          @logger.info "Image too small: #{i['width']}. Skipping"
          removed_images << i['url']
          next
        end

        # Only get images from existing article after checked Diffbot Image
        if second_pass && @article && @article['images'] && !@article['images'].empty? && @article['images'].first
          key_old = get_image_key(@article, i['url'])
          img_old = nil
          @article['images'].delete_if{|a| img_old = a if a['key'] == key_old }
          if img_old
            images << img_old
            unless i['url'] =~ /^http:\/\/res.cloudinary.com\/newsworthy/
              images_keys << { 'old_url' => i['url'], 'new_url' => img_old['url'] }
            end
            next
          end
        end

        if !quick && i['url'] =~ /.*\.gif$/
          key = get_image_key(@data, i['url'])
          images << { 'url' => convert_gif(i['url'], key), 'key' => key }
        else
          images << { 'url' => "https://res.cloudinary.com/newsworthy/image/fetch/w_750,c_limit,q_auto/#{i['url']}", 'key' => nil }
        end

        images_keys << { 'old_url' => i['url'], 'new_url' => images.last['url'] }
      end

      # Only get images from existing article after checked Diffbot Image
      if second_pass && @article && images.empty? && !@article['images'].empty?
        images = [@article['images'].shift]
      end

      if !quick && images.empty?
        @logger.info "No available images for \"#{@data['title']}\""

        # If it's the first pass and if we don't have any images, trying fetch image from Image API
        unless second_pass
          @logger.info "Check images from DiffBot for \"#{@data['title']}\""
          if get_images_from_diffbot
            @logger.info 'Images found from DiffBot. Retrying...'
            get_images_data(quick, true)
            return
          end
        end

        @logger.info "Try finding image with google for \"#{@data['title']}\""
        image = get_google_image
        if image
          @logger.info "Found image with google for \"#{@data['title']}\": #{image['url']}"
          images = [image]
        else
          # ApplicationController.error(@logger, "Can't find the image for article \"#{@data['title']}\"")
          @logger.warn "Can't find the image for article \"#{@data['title']}\""
        end
      end

      if @article && !@article['images'].empty?
        delete_old_images(images)
      end

      @data['images'] = images
      @data['content'] = remove_images(@data['content'], removed_images) unless removed_images.empty?
      replace_images_src(images_keys) unless images_keys.empty?
    end

    def remove_images(content, images)
      html_doc = Nokogiri::HTML(content)
      images.each do |i|
        elem = html_doc.at_xpath("//img[@src=\"#{i}\"]")
        find_image_element(elem).remove if elem
      end
      html_doc.search('body').children.to_html
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

    def delete_old_images(images)
      @article['images'].each do |i|
        if i['url'] =~ /^http:\/\/res.cloudinary.com\/newsworthy/
          # Delete image in Cloudinary if doesn't not exists in new images array
          if images.select {|d| d['key'] == i['key']}.empty?
            DeleteImage.perform_later(i['key'])
          end
        end
      end
    end

    def get_image_key(data, url)
      "#{Rails.env}/#{data['publication_name'] || URI(url).host}/#{Digest::MD5.hexdigest("#{url}#{data['title']}")}/#{Digest::MD5.hexdigest(url)}"
    end

    def get_google_image
      begin
        require 'google/apis/customsearch_v1'
        search = Google::Apis::CustomsearchV1::CustomsearchService.new
        search.key = Settings.google.search_api_key
        query = get_meaningcloud_entities("#{@data['title']} #{@data['site_name']}")
        result = nil

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
            image = { 'url' => "https://res.cloudinary.com/newsworthy/image/fetch/w_750,c_limit,q_auto/#{i.link}", 'key' => nil }
            # image = upload_google_image(i.link)
            break if image # Image uploaded, return url
          end
          image
        else
          nil # Return nil if no image returned
        end
      rescue Exception => e
        return ApplicationController.error(@logger, "Can't search for image using query: \"#{query}\"", e)
      end
    end

    def upload_google_image(url)
      key = get_image_key(@data, url)
      image = nil

      begin
        resp = Cloudinary::Uploader.upload(url, public_id: key, tags: [Rails.env, 'article'], width: 750, crop: :limit, quality: 80)
        if resp['width'] && resp['width'] < 300
          DeleteImage.perform_later(key)
          image = nil
        else
          image = { 'url' => resp['url'], 'key' => key }
        end
      rescue CloudinaryException => e
        @logger.warn("Cloudinary upload_image exception for #{url}: #{e.message}")
      rescue Exception => e
        @logger.warn("Cant upload image for #{url}: #{e.message}")
      end
      image
    end

    def get_meaningcloud_entities(query)
      info = nil
      begin
        Retriable.retriable do
          info = MeaningCloud::Topics.extract(txt: @data['text'])
        end
      rescue Exception => e
        ApplicationController.error(@logger, "Fail retry get_meaningcloud_entities MeaningCloud #{@data['url']}", e)
        return query
      end

      if info && info['status']['msg'] == 'OK' && info['entity_list'] && info['entity_list'].count > 0
        info['entity_list'].each do |c|
          if c['sementity']['type'] == 'Top'
            query = c['form']
            break
          end
        end
      else
        @logger.warn "No get_meaningcloud_entities data for #{@data['url']}"
        # ApplicationController.error(@logger, "No meaning_cloud data for #{@data['url']}: Status: #{info['status']['msg']} Credit: #{info['status']['remaining_credits']}", e)
      end
      query
    end

    def replace_images_src(images_keys)
      html_doc = Nokogiri::HTML(@data['content'])
      images_keys.each do |i|
        elem = html_doc.at_xpath("//img[@src=\"#{i['old_url']}\"]")
        elem['src'] = i['new_url'] if elem
      end
      @data['content'] = html_doc.search('body').children.to_html
    end

    def get_images_from_diffbot
      info = nil
      begin
        Retriable.retriable do
          info = Biffbot::Image.new(@data['url'])
        end
      rescue Exception => e
        @logger.warn "Can't find images from diffbot for #{@data['url']}: #{e.message}"
        return false
      end

      return false unless info

      if info['errorCode']
        if info['errorCode'] == 500
          @logger.warn "Diffbot API problem #{info['error']}"
        elsif info['errorCode'] == 429 || info['errorCode'] == 401
          ApplicationController.error(@logger, "Diffbot API problem: #{info['error']}")
        end
        return false
      end

      return false if info['type'] != 'image' || !info['images'] || info['images'].count <= 0

      images = []
      info['images'].each do |i|
        if i['type'] == 'image' && i['url']
          width = nil
          %w(naturalWidth width pixelWidth).each do |w|
            if i[w] && i[w] != 0
              width = i[w]
              break
            end
          end

          images << { 'url' => i['url'], 'key' => nil, 'width' => width }
        end
      end

      if images.count > 0
        @logger.info "Found #{images.count} new images from diffbot"
        @data['images'] = images
        true
      else
        @logger.info "Can't find new images from diffbot"
        false
      end
    end

    def banned_publication?(host)
      BannedPublication.where(name: host).exists?
    end

    def banned_extension?(url)
      begin
        exts =  %w(doc docx log msg odt pages rtf tex txt wpd wps csv dat ged key keychain pps ppt pptx sdf tar tax2014 tax2015 vcf aif iff m3u m4a mid mp3 mpa wav wma 3g2 3gp asf avi flv m4v mov mp4 mpg rm srt swf vob wmv 3dm 3ds max obj bmp dds gif jpg png psd pspimage tga thm tif tiff yuv ai eps ps svg indd pct pdf xlr xls xlsx accdb db dbf mdb pdb sql apk app bat com exe gadget jar wsf dem gam nes rom sav dwg dxf gpx kml kmz js rss crx plugin fnt fon otf ttf cab cpl cur deskthemepack dmp drv icns ico lnk sys cfg ini prf hqx mim uue 7z cbr deb gz pkg rar rpm sitx tar.gz zip zipx bin cue dmg iso mdf toast vcd c class cpp cs dtd fla h java lua m pl py sh sln swift vb vcxproj xcodeproj bak tmp crdownload ics msi part torrent)
        require 'addressable/uri'
        url = Addressable::URI.parse(url.to_s) unless url.class == Addressable::URI
        exts.include?(File.extname(url.path).gsub('.', ''))
      rescue Exception => e
        # @logger.warn("Fail retry small_page? #{url} - #{e.class}: '#{e.message}")
        ApplicationController.error(@logger, "Fail to get the extension for #{url} - #{e.class}: '#{e.message}")
      end
    end

    def invalid_content?(url)
      begin
        page = MetaInspector.new(url, { faraday_options: { ssl: false }})
        if page.response.status == 200
          size = (page.response.headers['content-length'] ? page.response.headers['content-length'].to_i : page.response.body.length)
          return size <= 3000
        end
      rescue MetaInspector::ParserError => e
        if e.message =~ /instead of text\/html content/
          true
        else
          # @logger.warn("Fail retry small_page? #{url} - #{e.class}: '#{e.message}")
          ApplicationController.error(@logger, "ParserError for invalid_content #{url} - #{e.class}: '#{e.message}")
        end
      rescue Exception => e
        @logger.warn("invalid_content for #{url} - #{e.class}: '#{e.message}")
        # ApplicationController.error(@logger, "invalid_content for #{url} - #{e.class}: '#{e.message}")
      end
    end

    def convert_gif(url, key)
      begin
        Retriable.retriable do
          image = Magick::ImageList.new(url)
          count = image.scene
          if count == 0
            return url # this is not an animated gif
          end
        end
      rescue Exception => e
        @logger.warn "Exception Magick::ImageList exception on #{url}: #{e.message}"
      end

      begin
        DeleteImage.perform_later(key)

        resp = nil
        Retriable.retriable do
          resp = Cloudinary::Uploader.upload(url, public_id: key, tags: Rails.env, width: 750, crop: :limit, format: 'mp4', quality: 80)
        end

        url = resp['url'] if resp && resp['url']
      rescue CloudinaryException => e
        @logger.warn "Cloudinary convert_gif exception: #{e.message}"
      rescue Exception => e
        @logger.warn "Exception convert_gif exception: #{e.message}"
      end

      url
    end
  end
end
