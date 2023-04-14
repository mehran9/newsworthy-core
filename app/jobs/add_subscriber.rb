# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class AddSubscriber < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger

  def perform(email)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start add subscriber #{email} to list at #{start_time.strftime('%H:%M:%S')}..."

    begin
      require 'createsend'

      auth = { api_key: Settings.createsend.api_key }
      ret = CreateSend::Subscriber.add(auth, Settings.createsend.list_id, email, '', nil, true)

      if ret == email
        @logger.info "Subscriber #{email} added in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
      else
        ApplicationController.error(@logger, "Can't add subscriber #{email} to list")
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Can't add Subscriber #{email}", e)
    end
  end
end
