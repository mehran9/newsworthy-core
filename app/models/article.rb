class Article
  include ParseModel

  after_destroy do |o|
    if o['images']
      o['images'].map do |i|
        next unless i['key']
        DeleteImage.perform_later(i['key'])
      end
    end

    %w(ArticleThoughtLeader ArticleIndustry ArticleNetwork ArticleTlMention ArticleMpMention ArticleNetworkMention ArticleMention).map do |object_class|
      object_class.constantize.where(owningId: o.id.to_s).destroy_all
    end

    %w(MentionArticle MentionIndustryTweetArticle MentionNetworkTweetArticle).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end

    %w(NetworkTweet IndustryTweet).map do |object_class|
      object_class.constantize.where(_p_Article: "Article$#{o.id}").destroy_all
    end

    %w(Network ThoughtLeader).map do |object_class|
      object_class.constantize.where('mentions.article_id': o.id.to_s).map do |n|
        n['mentions'].each_with_index do |m, i|
          n['mentions'].delete_at(i) if m['article_id'] == o.id.to_s
        end
        n.save
      end
    end

    Search.where(EntityId: o.id.to_s, EntityType: 'ThoughtLeaders').destroy_all
  end

  index({ md5_content: 1, url: 1, tweets_count: -1 }, { background: true })
  index({ publication_name: 1 }, { background: true })
  index({ 'tweets.user_id.objectId': 1 }, { background: true })
  index({ tweets_urls: 1 }, { background: true })
end
