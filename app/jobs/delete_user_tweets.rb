class DeleteUserTweets < ActiveJob::Base
  queue_as :low_priority

  def perform(main_class, object_id)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start DeleteUserTweets #{main_class}##{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    if main_class == 'ThoughtLeader'
      models = %w(Article IndustryTweet NetworkTweet Mention MentionIndustryTweet MentionNetworkTweet)

      models.map do |m|
        remove_user(m, object_id)
      end
    else
      models = %w(Article)

      models.map do |m|
        remove_user(m, object_id)
      end
    end

    @logger.info "DeleteTl #{object_id} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def remove_user(class_name, object_id)
    class_name.constantize.only(:tweets).where('tweets.user_id.objectId': object_id.to_s).map do |o|
      begin
        tweets = o['tweets'].select {|t| t['user_id']['objectId'].to_s != object_id.to_s }
        count = tweets.count
        if count != o['tweets'].count
          if count > 0
            @logger.info "Update #{class_name}##{o.id}"
            class_name.constantize.find(o.id).update(
                tweets: tweets,
                tl_count: count,
                tweets_count: tweets.map{ |m| m['tweets'].count }.sum,
                stats_all: count
            )
          else
            @logger.info "Delete #{class_name}##{o.id}"
            class_name.constantize.find(o.id).destroy
          end
        end
      rescue Exception => e
        # p "Can't remove tl #{object_id} in #{class_name}##{o.id}"
        ApplicationController.error(@logger, "Can't remove tl #{object_id} in #{class_name}##{o.id}", e)
      end
    end
  end
end
