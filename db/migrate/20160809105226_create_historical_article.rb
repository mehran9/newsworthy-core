class CreateHistoricalArticle < ActiveRecord::Migration
  class Schema
    include Mongoid::Document
    include Mongoid::Attributes::Dynamic

    store_in collection: '_SCHEMA'
  end

  def self.up
    unless Schema.where(_id: 'HistoricalArticle').exists?
      Schema.create(
          {
              '_id': 'HistoricalArticle',
              'category_ids': 'array',
              'language': 'string',
              'images': 'array',
              'text': 'string',
              'url': 'string',
              'topic': 'string',
              'tweets': 'array',
              'publication_name': 'string',
              'content': 'string',
              'title': 'string',
              'tweets_count': 'number',
              'site_name': 'string',
              'videos': 'array',
              'published_at': 'date',
              'author': 'string',
              'stats_4h': 'number',
              'stats_2d': 'number',
              'stats_1h': 'number',
              'stats_8h': 'number',
              'stats_1w': 'number',
              'stats_2h': 'number',
              'stats_2w': 'number',
              'stats_1d': 'number',
              'stats_3d': 'number',
              'webviewonly': 'boolean',
              'md5_content': 'string',
              'FetchedImage': 'boolean',
              'ThoughtLeaders': 'relation<ThoughtLeaders>',
              'MentionedPerson': 'relation<MentionedPerson>',
              'stats_3m': 'number',
              'stats_all': 'number',
              'stats_1m': 'number',
              'SubCategories': 'array',
              'Categories': 'array'
          }
      )
    end
  end

  def self.down
    Schema.where(_id: 'HistoricalArticle').destroy_all
  end
end
