class UpdateTl < ActiveJob::Base
  queue_as :low_priority

  def perform(twitter_id, class_name)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start UpdateTl #{class_name} #{twitter_id} at #{start_time.strftime('%H:%M:%S')}..."

    tl = class_name.constantize.where(twitter_id: twitter_id.to_s).first

    @logger.warn "#{class_name} #{twitter_id} not found. Exiting" and return unless tl

    begin
      Retriable.retriable do |i|
        if i == 3
          @logger.info "Update information for #{twitter_id} without proxy..."
          client = Utils.twitter_client
        else
          proxy = "http://#{Settings.proxies.sample}"
          @logger.info "Update information for #{twitter_id} with proxy #{proxy}..."
          client = Utils.twitter_client(nil, proxy)
        end
        begin
          u = client.user(twitter_id.to_i)
          if u
            tl.update({
                          display_name: (u.name? ? u.name.gsub('(', '').gsub(')', '') : nil),
                          avatar: Utils.get_twitter_avatar(u),
                          summary: (u.description? ? u.description : nil),
                          country: (u.location? ? u.location : nil),
                          language: (u.lang? ? u.lang : nil),
                          followers_count: (u.followers_count ? u.followers_count : 0),
                          profile_updated_at: Time.now
                      })
            if class_name == 'ThoughtLeader'
              search = Search.where(EntityId: tl.id, EntityType: 'ThoughtLeaders').first
              if search
                search.update({
                                 EntityMedia: tl['avatar'],
                                 EntityName: tl['display_name'],
                                 EntityNameLC: tl['display_name'].downcase
                             })
              end
            end
          else
            raise Twitter::Error::NotFound
          end
        rescue Twitter::Error::NotFound => e
          @logger.warn "#{twitter_id} not found"
          disable_user(tl) if class_name == 'ThoughtLeader'
          break
        rescue Twitter::Error::Forbidden => e
          @logger.warn "#{twitter_id} has been suspended"
          disable_user(tl) if class_name == 'ThoughtLeader'
          break
        rescue Twitter::Error::TooManyRequests
          @logger.warn "TooManyRequests for #{twitter_id}"
          break
        end
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Fail getting information for #{twitter_id}", e)
    end

    @logger.info "UpdateTl #{twitter_id} finished in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def disable_user(tl)
    @logger.warn "Disabling user #{tl['twitter_id']} (#{tl.id})..."
    tl.update({profile_updated_at: Time.now, disabled: true})
    Search.where(EntityId: tl.id, EntityType: 'ThoughtLeaders').destroy
    # articles_ids = ArticleThoughtLeader.where(relatedId: tl.id).pluck(:owningId)
    # unless articles_ids.empty?
    #   Article.in(id: articles_ids).map do |a|
    #     a['tweets']
    #   end
    # end
  end
end
