class ArticleTlMention
  @collection = '_Join:tl_mention:Article'
  include ParseModel

  index({ owningId: 1, relatedId: 1 }, { background: true, unique: true })
  index({ owningId: 1, relatedId: -1 }, { background: true, unique: true })
  index({ owningId: 1 }, { background: true })
  index({ relatedId: 1 }, { background: true })
end
