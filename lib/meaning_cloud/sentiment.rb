module MeaningCloud
  # A class to hold sentiment extraction related code.
  class Sentiment
    def self.extract(options = nil)
      fail(Exception, 'Missing key') if MeaningCloud.configuration.key.nil?

      options ||= {}

      options = {
          key: MeaningCloud.configuration.key,
          lang: 'en',
          uw: 'y'
      }.merge(options)

      endpoint = 'sentiment-2.1'

      result = RestClient.post("#{API_BASE}#{endpoint}", options)
      JSON.parse(result)
    end
  end
end
