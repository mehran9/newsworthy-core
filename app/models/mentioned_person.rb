class MentionedPerson
  include ParseModel

  after_destroy do |o|
    %w(MentionedPersonIndustry MentionedPersonNetwork).map do |object_class|
      object_class.constantize.where(owningId: o.id.to_s).destroy_all
    end

    %w(ArticleMpMention).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end
  end

  index({ profile_updated_at: 1, disable: 1 }, { background: true })
  index({ twitter_id: 1 }, { background: true })
end
