class HistoricalArticleMentionedPerson
  @collection = '_Join:MentionedPerson:HistoricalArticle'
  include ParseModel

  index({ owningId: 1, relatedId: 1 }, { background: true, unique: true })
  index({ owningId: 1, relatedId: -1 }, { background: true, unique: true })
end
