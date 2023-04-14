class Network
  include ParseModel

  after_destroy do |o|
    DeleteImage.perform_later(o['LogoURL']) if o['LogoURL'] && !o['LogoURL'].empty?
    DeleteImage.perform_later(o['IconURL']) if o['IconURL'] && !o['IconURL'].empty?

    %w(ArticleNetwork MentionNetwork ThoughtLeaderNetwork UserNetwork ArticleNetworkMention MentionedPersonNetwork).map do |object_class|
      object_class.constantize.where(relatedId: o.id.to_s).destroy_all
    end

    %w(MentionNetworkTweet NetworkTweet Search).map do |object_class|
      object_class.constantize.where(_p_Network: "Network$#{o.id}").destroy_all
    end
  end
end
