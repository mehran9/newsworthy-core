class BetaGroup
  @collection = 'BetaGroups'
  include ParseModel

  index({ shares: 1 }, { background: true })
end
