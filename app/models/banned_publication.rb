class BannedPublication
  include ParseModel

  index({ name: 1 }, { unique: true, background: true })
end
