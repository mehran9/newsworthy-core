class UpdateScores < ActiveJob::Base
  queue_as :low_priority

  # @param [ObjectId] object_id Parse TL id
  def perform(object_id, class_name)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start UpdateScores for #{class_name}##{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    object = class_name.constantize.where(id: object_id).first

    begin
      if object
        object['mentions'].map do |m|
          m['mention_score'] = Utils.get_float(m['mention_score'])
        end
        object['average_mention_score'] = calculate_ms(object)
        object['average_article_score'] = calculate_as(object, 'ArticleThoughtLeader') if class_name == 'ThoughtLeader'
        object['average_network_score'] = calculate_ns(object, (class_name == 'ThoughtLeader' ? 'ThoughtLeaderNetwork': 'MentionedPersonNetwork'))
        object['score'] = calculate_score(object)

        object.save
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Fail saving score for #{class_name}##{object_id}", e)
    end

    @logger.info "UpdateScores finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def calculate_ms(tl)
    sum = 0
    tl['mentions'].map do |m|
      sum += m['mention_score'] if m['mention_score']
    end
    total = sum.to_f / tl['mentions'].count
    Utils.get_float(total)
  end

  def calculate_as(tl, class_name)
    articles_ids = class_name.constantize.where(relatedId: tl.id).pluck(:owningId)

    score = 0

    if articles_ids && !articles_ids.empty?
      sum = 0
      Article.in(id: articles_ids).pluck(:score).map do |t|
        sum += t if t
      end
      score = sum.to_f / articles_ids.count
    end

    Utils.get_float(score)
  end

  def calculate_ns(tl, class_name)
    networks_ids = class_name.constantize.where(owningId: tl.id).pluck(:relatedId)

    score = 0

    if networks_ids && !networks_ids.empty?
      sum = 0
      Network.in(id: networks_ids).pluck(:score).map do |t|
        sum += t if t
      end
      score = sum.to_f / networks_ids.count
    end

    Utils.get_float(score)
  end

  def calculate_score(tl)
    total = (tl['average_mention_score'] + tl['average_article_score'] + tl['average_network_score']) / 3.to_f
    Utils.get_float(total, 1)
  end
end
