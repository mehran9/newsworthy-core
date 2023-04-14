class ThoughtLeader
  @collection = 'ThoughtLeaders'
  include ParseModel

  after_destroy do |o|
    %w(ThoughtLeaderIndustry ThoughtLeaderNetwork).map do |object_class|
      object_class.constantize.where(owningId: o.id.to_s).destroy_all
    end

    %w(ArticleThoughtLeader ArticleTlMention).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end

    Search.where(EntityId: o.id, EntityType: 'ThoughtLeaders').destroy_all

    DeleteUserTweets.perform_later('ThoughtLeader', o.id.to_s)
  end

  index({ twitter_id: 1 }, { background: true })
  index({ profile_updated_at: 1, disable: 1 }, { background: true })
end
