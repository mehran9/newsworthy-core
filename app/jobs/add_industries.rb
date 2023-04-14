# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class AddIndustries < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger         # Logger for debug / info message
  attr_accessor :object         # Current _User or ThoughtLeaders

  # @param [ObjectId] object_id Parse Object id
  def perform(object_id, class_name)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start AddIndustries at #{start_time.strftime('%H:%M:%S')}..."

    @logger.info 'Fetch object from db...'
    @object = class_name.constantize.where(id: object_id.to_s).first

    return ApplicationController.error(@logger, "Can't find #{class_name}##{object_id}") unless @object

    networks_ids = (class_name == '_User' ? UserNetwork : ThoughtLeaderNetwork).where(owningId: object_id.to_s).pluck(:relatedId)

    if networks_ids && !networks_ids.empty?
      Network.in(id: networks_ids).map do |n|
        if n['Industry']
          @logger.info "Add Industry #{n['Industry'].id} to ##{object_id}..."
          @object.array_add_relation('Industries', n['Industry'])
        end
      end

      @logger.info "Save object #{class_name}##{object_id} to parse..."
      Retriable.retriable do
        @object.save
      end
    end

    @logger.info "Information found in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
