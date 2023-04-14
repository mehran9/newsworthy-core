class Publisher
  include ParseModel

  after_destroy do |o|
    DeleteImage.perform_later(o['logo']) if o['logo'] && !o['logo'].empty?
    DeleteImage.perform_later(o['icon']) if o['icon'] && !o['icon'].empty?

    Search.where(EntityId: o.id, EntityType: 'Publisher').destroy_all
  end

  index({ publication_name: 1 }, { background: true })
end
