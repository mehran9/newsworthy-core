class MentionNetworkTweet
  @collection = 'MentionNetworkTweets'
  include ParseModel

  index({ _p_Network: 1, _p_Mention: 1 }, { background: true })
  index({ 'tweets.user_id.objectId': 1}, { background: true })
end
