class MentionIndustryTweet
  @collection = 'MentionIndustryTweets'
  include ParseModel

  index({ _p_Industry: 1, _p_Mention: 1 }, { background: true })
  index({ 'tweets.user_id.objectId': 1}, { background: true })
end
