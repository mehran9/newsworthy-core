class Mention
  include ParseModel

  after_destroy do |o|
    %w(MentionArticle MentionIndustry MentionNetwork).map do |object_class|
      object_class.constantize.where(owningId: o.id.to_s).destroy_all
    end

    %w(ArticleMention).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end

    %w(MentionNetworkTweet MentionIndustryTweet).map do |object_class|
      object_class.constantize.where(_p_Mention: "Mention$#{o.id}").destroy_all
    end
  end

  index({ name: 1, type: 1 }, { background: true })
  index({ 'tweets.user_id.objectId': 1}, { background: true })
end
