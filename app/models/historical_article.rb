class HistoricalArticle
  include ParseModel

  index({ md5_content: 1, url: 1, tweets_count: -1 }, { background: true })
  index({ publication_name: 1 }, { background: true })
  index({ tweets_urls: 1 }, { background: true })

  after_destroy do |o|
    %w(HistoricalArticleMentionedPerson HistoricalArticleThoughtLeader).map do |object_class|
      object_class.constantize.where(owningId: o.id.to_s).destroy_all
    end
  end
end
