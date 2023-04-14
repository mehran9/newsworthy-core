# Define logger for this task, to output in file
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = (Rails.env.development? ? Logger::DEBUG : Logger::ERROR)

# Those tasks are launched using crontab
# See config/schedule.rb to see which are active
namespace :generate_graph do
  task :all => :environment do
    start_time = Time.now
    Rails.logger.info "Start generate_graph at #{start_time.strftime('%H:%M:%S')}..."

    # models = %w(Mention MentionIndustryTweet MentionNetworkTweet)
    models = %w(Mention)
    require 'ruby-prof'

    models.map do |c|
      generate_graph(c)
    end

    Rails.logger.info "Task finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  task :fix_date => :environment do
    start_time = Time.now
    Rails.logger.info "Start fix_date at #{start_time.strftime('%H:%M:%S')}..."

    models = %w(Mention MentionIndustryTweet MentionNetworkTweet)

    models.map do |object_class|
      objects = []
      object_class.constantize.all.map do |a|
        if a['sentiment_score'] && !a['sentiment_score'].empty?
          changed = false
          scores = []
          a['sentiment_score'].map do |s|
            if s['date'].is_a?(String)
              s['date'] = Time.parse(s['date'])
              changed = true
            elsif s['date'].is_a?(Hash)
              s['date'] = Time.parse(s['date']['iso'])
              changed = true
            end
            scores << s
          end
          if changed
            objects << { update_one: { filter: { _id: a.id }, update: { '$set' => {
                "sentiment_score": scores
            }}}}
          end
        end
      end
      p object_class.constantize.collection.bulk_write(objects)
    end

    Rails.logger.info "Task fix_date finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  def generate_graph(object_class)
    start_time = Time.now
    Rails.logger.info "-> Start updating graph for #{object_class} at #{start_time.strftime('%H:%M:%S')}..."

    ranges = [
        { key: '1h', value: 1, type: 'hours' },
        { key: '2h', value: 2, type: 'hours' },
        { key: '4h', value: 4, type: 'hours' },
        { key: '8h', value: 8, type: 'hours' },
        { key: '1d', value: 24, type: 'hours' },
        { key: '2d', value: 48, type: 'hours' },
        { key: '3d', value: 72, type: 'hours' },
        { key: '1w', value: 168, type: 'hours' }, # 1 week
        { key: '2w', value: 14, type: 'days' },
        { key: '1m', value: 31, type: 'days' },
        { key: '3m', value: 93, type: 'days' },
    ]

    # RubyProf.start

    objects = []
    fields = :sentiment_score, ranges.flat_map{|r| %W(sentiment_graph_data_#{r[:key]}) }
    object_class.constantize.only(fields).where(:_updated_at.gte => ranges.last[:value].send(ranges.last[:type]).ago).map do |a|
      if a['sentiment_score'] && !a['sentiment_score'].empty?
        ranges.each do |r|
        # Parallel.map(ranges.map, in_threads: (Rails.env.production? ? 8 : 1)) do |r|
          begin
            values = (1..r[:value]).map do |t|
              value = a['sentiment_score'].select {|s| s['date'] >= t.send(r[:type]).ago }.map{|s| s['score'] }
              if value.empty?
                0
              else
                value.sum.to_f
              end
            end

            values.reverse!

            if values.count == 1
              values << values.first # 1h need at least 2 points
            end

            md5 = Digest::MD5.hexdigest values.to_yaml
            field = a["sentiment_graph_data_#{r[:key]}"]
            unless field && field['key'] =~ /#{md5}/
              image = create_image(values, "sentiment_graph_data_#{r[:key]}_#{md5}")
              # image = upload_image(file, "sentiment_graph_data_#{r[:key]}_#{md5}")
              delta = values.first - values.last
              File.unlink(file)
              objects << { update_one: { filter: { _id: a.id }, update: { '$set' => {
                  "sentiment_graph_data_#{r[:key]}": image,
                  "sentiment_delta_score_#{r[:key]}": delta
              }}}}
            end
          rescue Exception => e
            ApplicationController.error(Rails.logger, "Fail to create graph for #{object_class}##{a.id} #{r[:value]} #{r[:type]}", e)
          end
        end

        if objects.count > 0
          Rails.logger.info object_class.constantize.collection.bulk_write(objects)
        end
      end
    end

    # if objects.count > 0
    #   Rails.logger.info object_class.constantize.collection.bulk_write(objects)
    # end

    # result = RubyProf.stop
    # printer = RubyProf::GraphPrinter.new(result)
    # printer.print(Tempfile.new(%w(generate_graph .txt), File.join(Rails.root, 'tmp')), :min_percent => 2)
    # printer.print(STDOUT, :min_percent => 5)

    Rails.logger.info "-> Updated graph for #{object_class} in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}"
  end

  def create_image(values, key)
    file = "./tmp/#{key}.png"
    # file = "./tmp/test.png"
    width = 750.to_f
    height = 150.to_f
    img = Magick::Image.new(width, height) { self.background_color = 'transparent' }

    gc = Magick::Draw.new
    gc.stroke_width(2)
    gc.fill('transparent')
    gc.stroke_dasharray(20, 10)
    gc.stroke('grey')
    gc.line(0, height / 2, width, height / 2)
    gc.draw(img)

    gc = Magick::Draw.new
    gc.stroke('white')
    gc.stroke_linecap('round')
    # gc.stroke_linejoin('round')
    gc.fill('transparent')
    gc.stroke_width(4)
    gc.translate(0, height / 2)

    last_x = nil
    last_y = nil
    max_y = (values.max > -values.min ? values.max : -values.min)
    max_y = 1 if max_y == 0
    x = width / (values.count - 1).to_f
    y = ((height - 8) / (max_y * 2)).to_f

    values.each_with_index do |v, i|
      point_x = i * x
      point_y = -v.to_f * y
      if last_x
        gc.line(last_x, last_y, point_x, point_y)
      end
      last_x = point_x
      last_y = point_y
    end

    gc.draw(img)
    img.write(file)
    Base64.strict_encode64(File.open(file, 'rb').read)
    file
  end

  def upload_image(file, key)
    image = nil

    begin
      resp = Cloudinary::Uploader.upload(file, public_id: "#{Rails.env}/graph/#{key}", tags: [Rails.env, 'graph'], overwrite: false)
      image = { 'url' => resp['secure_url'], 'key' => "#{Rails.env}/graph/#{key}" }
    rescue CloudinaryException => e
      Rails.logger.warn "Cloudinary upload_image exception for #{file}: #{e.message}"
    rescue Exception => e
      Rails.logger.warn "Cant upload image for #{file}: #{e.message}"
    end
    image
  end
end
