require 'json'
require 'rest_client'
require 'meaning_cloud/topics'
require 'meaning_cloud/text_classification'

# Top level name space for the entire Gem.
module MeaningCloud
  API_BASE = 'https://api.meaningcloud.com/' unless defined?(API_BASE)

  def self.configuration
    @configuration ||=  Configuration.new
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration) if block_given?
  end

  # Main configuration class.
  class Configuration
    attr_accessor :key

    def initialize
      @key = nil
    end
  end
end
