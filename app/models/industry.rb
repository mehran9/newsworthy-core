class Industry
  include ParseModel

  after_destroy do |o|
    %w(ArticleIndustry MentionIndustry ThoughtLeaderIndustry UserIndustry MentionedPersonIndustry).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end

    %w(MentionIndustryTweet IndustryTweet Network Search).map do |object_class|
      object_class.constantize.where(_p_Industry: "Industry$#{o.id}").destroy_all
    end
  end
end
