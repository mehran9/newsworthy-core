module MeaningCloud
  # A class to hold all topic extraction related code.
  class Topics
    def self.extract(options = nil)
      fail(Exception, 'Missing key') if MeaningCloud.configuration.key.nil?

      options ||= {}

      options = {
        key: MeaningCloud.configuration.key,
        lang: 'en',
        tt: 'e',
        uw: 'y'
      }.merge(options)

      endpoint = 'topics-2.0'

      result = RestClient.post("#{API_BASE}#{endpoint}", options)
      JSON.parse(result)
    end
  end
end
