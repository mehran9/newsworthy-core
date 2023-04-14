# No more used

namespace :export do
  task :articles => :environment do
    require 'csv'
    get_articles
    get_tweets
  end

  task :to_parse => :environment do
    Article.find_each do |a|
      begin
        article = Parse::Query.new('Article').eq('url', a.url).get.first

        unless article
          data = {
            url:  a.url,
            title: a.title,
            publication_name: a.publication_name,
            published_at: a.published_at,
            content: a.content,
            author: a.author,
            language: a.language,
            images: a.images.map {|i| {url: i.url, key: i.key}},
            videos: [],
            tweets: get_tweets_data(a.tweets),
            category_ids: get_meaning_cloud_data(a)
          }
          Parse::Object.new('Article', data).save
        end
      rescue Exception => e
        Rails.logger.warn "Can't save article: #{e.class}: '#{e.message}"
      end
    end
  end

  task :all => [:articles]
  task :default => [:articles]

  def get_articles
    file = File.join(Rails.root, 'tmp', 'export_articles.csv')
    CSV.open(file, 'wb') do |csv|
      csv << %w(url tweets_count publication_name title author language published_at categories)
      Article.find_each do |a|
        data = [a.url, a.tweets_count, a.publication_name, a.title, a.author, a.language, a.published_at]
        categories = ''
        hash_tree = a.categories.hash_tree rescue nil
        if hash_tree
          hash_tree.each do |c|
            categories << "#{parse_categories(c)}\n"
          end
          data << categories[0..-2]
        else
          data << ''
        end
        csv << data
      end
    end
    p exec "curl --upload-file #{file} https://transfer.sh"
    File.delete file
  end

  def get_tweets
    file = File.join(Rails.root, 'tmp', 'export_tweets.csv')
    CSV.open(file, 'wb') do |csv|
      csv << %w(twitter_id content user.tweets_count user.name user.display_name user.avatar user.summary user.country user.language)
      Tweet.find_each do |t|
        csv << [t.twitter_id, t.content, t.user.tweets_count, t.user.name, t.user.display_name, t.user.avatar, t.user.summary, t.user.country, t.user.language]
      end
    end
    p exec "curl --upload-file #{file} https://transfer.sh"
    File.delete file
  end

  def parse_categories(c, cat = '')
    c.each do |c1|
      if c1.class == ActiveSupport::OrderedHash || c1.class == Array
        parse_categories(c1, cat)
      else
        cat << "#{c1['name']} > "
      end
    end
    cat[0..-4]
  end

  def get_tweets_data(tweets)
    tweets.map do |t|
      begin
        user = Parse::Query.new('ThoughtLeaders').eq('twitter_id', t.user.twitter_id.to_s).get.first
        unless user
          user = Parse::Object.new('ThoughtLeaders', {
            twitter_id: t.user.twitter_id,
            name: t.user.name,
            display_name: t.user.display_name,
            avatar: t.user.avatar,
            summary: t.user.summary,
            country: t.user.country,
            language: t.user.language
          })
          user.save
        end
        {tweet_id: t.twitter_id, tweet_content: t.content, user_name: t.user.name, user_tweeter_id: t.user.twitter_id, user_id: user.pointer}
      rescue Exception => e
        Rails.logger.warn "Can't save user: #{e.class}: '#{e.message}"
      end
    end
  end

  def get_meaning_cloud_data(data)
    if data.language.present?
      model = "IPTC_#{data.language}"
    else
      model = 'IPTC_en'
    end
    categories = []
    info = MeaningCloud::TextClassification.extract(title: data.title, txt: data.content, model: model)
    if info && info['status']['msg'] == 'OK'
      info['category_list'].map do |c|
        categories << c['code']
      end
    else
      Delayed::Worker.logger.debug "No meaning_cloud data for #{data.url}"
    end
    categories
  end
end
