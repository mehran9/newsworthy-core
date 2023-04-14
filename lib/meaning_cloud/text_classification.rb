module MeaningCloud
  class TextClassification
    # options: https://www.meaningcloud.com/developer/text-classification/doc/1.1/request
    def self.extract(options = nil)
      fail(Exception, 'Missing key') if MeaningCloud.configuration.key.nil?

      options ||= {}

      options = {
        key: MeaningCloud.configuration.key
      }.merge(options)

      fail(Exception, 'Missing model') unless options[:model].present?
      fail(Exception, 'Missing text or url') unless options[:txt].present? || options[:url].present?

      endpoint = 'class-1.1'

      result = RestClient.post("#{API_BASE}#{endpoint}", options)
      JSON.parse(result)
    end
  end
end
