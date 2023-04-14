class UpdateArticle < ActiveJob::Base
  queue_as :default

  attr_accessor :logger

  def perform(object_id, url)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start updating article #{object_id} at #{start_time.strftime('%H:%M:%S')}..."

    begin
      article = Article.where(id: object_id).first

      @logger.info "Can't find article #{object_id}. Exiting" and return unless article

      fetch = Fetching::Content.new({ logger: @logger, article: article })
      data = fetch.get_content(url)

      @logger.info "No data for article #{object_id}. Exiting" and return unless data

      data.delete('icon')

      article.update(data)

      Utils.search_and_merge(article)

      @logger.info "Article #{object_id} updated in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
    rescue Exception => e
      unless e.message == '116: The object is too large -- should be less than 128 kB.'
        ApplicationController.error(@logger, "Can't update article #{object_id}", e)
      end
    end
  end
end
