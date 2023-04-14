class FollowUser < ActiveJob::Base
  queue_as :low_priority

  def perform(action, twitter_id)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start #{action} TL #{twitter_id} at #{start_time.strftime('%H:%M:%S')}..."

    tl = ThoughtLeader.where(twitter_id: twitter_id.to_s).first

    unless tl
      ApplicationController.error(@logger, "#{action} ThoughtLeader #{twitter_id} not found. Exiting")
      return
    end

    unless tl.streamer
      ApplicationController.error(@logger, "#{action} ThoughtLeader #{twitter_id} with empty streamer. Exiting")
      return
    end

    if action == 'unfollow'
      streamer = Streamer.where(id: tl.streamer.id).first

      unless streamer
        ApplicationController.error(@logger, "#{action} Streamer #{tl.streamer.id} not found. Exiting")
        return
      end

      s = Settings.streamers.select{|s| s.topic.parameterize == streamer.topic}.first
      unless s
        ApplicationController.error(@logger, "#{action} Streamer #{streamer.topic} not found in config. Exiting")
        return
      end
    else
      s = Settings.streamers.sample

      streamer = Streamer.where(topic: s.topic.parameterize).first

      unless streamer
        ApplicationController.error(@logger, "#{action} Streamer #{tl.streamer.id} not found. Exiting")
        return
      end
    end

    client = Utils.twitter_client(s)

    begin
      if action == 'unfollow'
        client.unfollow(twitter_id.to_i)
        tl.update(streamer: nil)
        @logger.info "Unfollow user #{twitter_id}"
      else
        ret = client.follow(twitter_id.to_i)
        if ret.count != 1
          @logger.info "Already following user #{twitter_id}"
        else
          @logger.info "Follow new user #{twitter_id}"
        end

        tl.update(streamer: streamer)
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Can't #{action} #{twitter_id.to_i}", e)
    end

    @logger.info "#{action} TL finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end
end
