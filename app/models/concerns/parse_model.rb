module ParseModel
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Attributes::Dynamic

    store_in collection: (defined?(@collection) ? @collection : self.to_s)

    # Add timestamps only for not relationship tables
    unless self.storage_options[:collection].to_s.match(/^_Join:/)
      include Mongoid::Timestamps

      self.fields.delete('created_at')
      self.fields.delete('updated_at')
      field :_created_at, type: Time, as: :created_at
      field :_updated_at, type: Time, as: :updated_at

      # Transform mongoid ObjectId to string
      field :_id, type: String, pre_processed: true, default: ->{ BSON::ObjectId.new.to_s }, overwrite: true
    end

    # Create dynamic 1:1 relationship like _p_Model: from 'Model': Pointer to 'Model$record_id'
    before_save do |obj|
      schema = Schema.where(id: obj.storage_options[:collection].to_s).first
      if schema
        obj.attributes.to_a.each do |k,v|
          if v && v.class == Parse::Pointer && schema[k] == "*#{v.class_name}"
            obj.attributes.delete(k)
            obj["_p_#{k}"] = "#{v.class_name}$#{v.id}"
          end
        end
      end
    end

    # Create dynamic 1:1 relationship like _p_Model: from 'Model$record_id' to 'Model': Pointer
    after_find do |obj|
      obj.attributes.to_a.each do |k,v|
        if v && v.is_a?(String)
          match = k.match(/^_p_(.*)/) # match '_p_Model'
          if match && match[1]
            id = v.match(/^(.*)\$(.*)$/) # match 'Model$record_id'
            if id && id[1] && id[2]
              obj.attributes.delete(k)
              # Ugly fix for TL class_name
              class_name = (id[1] == 'ThoughtLeaders' ? 'ThoughtLeader' : id[1])
              obj[match[1]] = class_name.constantize.new(id: id[2]).pointer
            end
          end
        end
      end
    end
  end

  class Schema
    include Mongoid::Document
    include Mongoid::Attributes::Dynamic

    store_in collection: '_SCHEMA'
  end

  def pointer
    Parse::Pointer.new({'className' => self.storage_options[:collection].to_s, 'objectId' => self.id.to_s})
  end

  # Create dynamic 1:n relationship like _p_Model: 'Model$record_id'
  def array_add_relation(field, pointer)
    relation = find_relation(self.class, field)
    return false unless relation

    # We can only store relationship after related id is created
    if self.new_record?
      ApplicationController.error(Rails.logger, 'WARN: You have to save the record before using array_add_relation')
      return false
    end

    # join = relation.match(/<(.*)>/)[1]

    # Create a temporary class for this relation
    table_name = self.storage_options[:collection].to_s
    join_table = "JoinTable_#{BSON::ObjectId.new.to_s}"
    Object.const_set(join_table, Class.new {
      @collection = "_Join:#{field}:#{table_name}"
      include ParseModel
    })

    # Create the relationship
    join_table.constantize.where(owningId: self.id, relatedId: pointer.id.to_s).find_or_create_by

    # Remove the temporary class
    Object.send(:remove_const, join_table.to_sym)
  end

  private

  def find_relation(related_class, field)
    # Load table schema
    schema = Schema.where(id: related_class.storage_options[:collection].to_s).first
    unless schema
      ApplicationController.error(Rails.logger, "#{related_class.to_s} is not declared in the _SCHEMA table for array_add_relation")
      return false
    end

    # Find corresponding relationship
    if schema[field]
      true
    else
      ApplicationController.error(Rails.logger, "WARN: No relation for #{field} in #{related_class.to_s} class")
      false
    end
  end
end
