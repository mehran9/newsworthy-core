class User
  @collection = '_User'
  include ParseModel

  index({ email: 1}, { background: true })
end
