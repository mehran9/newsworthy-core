class IndustryTweet
  @collection = 'IndustryTweets'
  include ParseModel

  index({ 'tweets.user_id.objectId': 1}, { background: true })
end
