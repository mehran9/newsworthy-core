class DeleteImage < ActiveJob::Base
  queue_as :low_priority

  def perform(key)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start DeleteImage for #{key} at #{start_time.strftime('%H:%M:%S')}..."

    begin
      Retriable.retriable do
        Cloudinary::Uploader.destroy(key)
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Fail to delete image #{key}", e)
    end

    @logger.info "DeleteImage #{key} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
