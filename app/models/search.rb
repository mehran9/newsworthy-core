class Search
  include ParseModel

  index({ EntityId: 1, EntityType: 1 }, { background: true })
  index({ EntityType: 1, EntityName: 1 }, { background: true })
end
