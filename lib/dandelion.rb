# -*- encoding : utf-8 -*-

module Dandelion
  class API
    attr_accessor :logger

    def initialize(opts = {})
      @logger = opts[:logger] || Logger.new(STDOUT).tap{|l|
        l.level = "Logger::#{Rails.application.config.log_level.to_s.upcase}".constantize
      }
    end

    def fetch(name, opts = nil)
      objects = []
      keys = Settings.dandelion.sample
      Dandelionapi.configure do |c|
        c.app_id = keys.app_id
        c.app_key = keys.app_key
        c.endpoint = 'https://api.dandelion.eu/'
      end
      element = Dandelionapi::EntityExtraction.new
      begin
        response = nil
        Retriable.retriable do
          response = element.analyze(text: name, lang: 'en', min_confidence: '0.2', include: 'types,image,lod', 'social.hashtag': true, 'social.mention': true, epsilon: '0.5')
        end
        new_elem = false
        if response['error']
          ApplicationController.error(@logger, "Found Dandelionapi an error #{response['message']}")
          return false
        end
        if response['annotations'] && response['annotations'].is_a?(Array) && response['annotations'].count > 0
          response['annotations'].each do |a|
            if a['types'] && a['types'].is_a?(Array) && a['types'].count > 0
              if objects.select{|n| n[:NetworkName] == a['label'] }.empty?
                if a['types'].grep(/^http:\/\/dbpedia.org\/ontology\/(Organisation|Company|Newspaper|Website|Software)/).empty?
                  @logger.info "Bad types for network '#{a['label']}' #{a['lod']['dbpedia']}: #{a['types'].to_sentence}"
                else
                  objects << {
                      NetworkName: a['label'],
                      NetworkUrl: a['lod']['dbpedia'],
                      Hidden: false
                  }.merge(opts)
                  @logger.info "Found network '#{a['label']}' with types #{a['types'].to_sentence}"
                end
              else
                @logger.info "Network '#{a['label']}' already selected"
              end

              new_elem = true
            elsif a['lod'] && a['lod']['dbpedia']
              # No types, that's weird.. Let's check dbpedia page and found it ourself..
              @logger.info "No types for network '#{a['label']}', extracting types from dbpedia link..."

              page = nil
              Retriable.retriable do
                page = MetaInspector.new(a['lod']['dbpedia'], { faraday_options: { ssl: false }})
              end
              return false unless page

              res = page.parsed.search("//a[@href='http://www.w3.org/1999/02/22-rdf-syntax-ns#type']").first
              if res
                types = res.parent.parent.search('td:nth-child(2) > ul > li a[@rel="rdf:type"]').map(&:text)

                if types && types.is_a?(Array) && types.count > 0
                  unless types.grep(/^dbo:(Organisation|Company|Newspaper|Website|Software)/).empty?
                    objects << {
                        NetworkName: a['label'],
                        NetworkUrl: a['lod']['dbpedia'],
                        Hidden: false
                    }.merge(opts)
                    @logger.info "Found network '#{a['label']}' using dbpedia link with types #{types.to_sentence}"
                  end
                  new_elem = true
                end
              end
            end
          end
        end
        if objects.select{|n| n[:NetworkName] == name}.empty? && !new_elem
          @logger.info "Add network '#{name}' as hidden"
          objects << { NetworkName: name, Hidden: true }.merge(opts)
        end
      rescue Exception => e
        # @logger.warn("Can't find information for AddNetworks #{name}: #{e.message}")
        ApplicationController.error(@logger, "Can't find information for AddNetworks \"#{name}\"", e)
      end
      objects
    end
  end
end
