class NetworkTweet
  @collection = 'NetworkTweets'
  include ParseModel

  index({ 'tweets.user_id.objectId': 1}, { background: true })
  index({ _p_Article: 1 }, { background: true })
  index({ _p_Network: 1 }, { background: true })
end
