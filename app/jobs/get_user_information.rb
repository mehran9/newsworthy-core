# noinspection RubyStringKeysInHashInspect,RubyStringKeysInHashInspection

class GetUserInformation < ActiveJob::Base
  queue_as :low_priority

  attr_accessor :logger         # Logger for debug / info message
  attr_accessor :object         # Current User or ThoughtLeaders
  attr_accessor :industries     # Freshly created industries
  attr_accessor :original_logo

  # @param [ObjectId] object_id Parse Object id
  # @param [String] class_name Parse Class name (User or ThoughtLeaders)
  # @param [Hash] data Email, Twitter, Facebook and Name
  def perform(object_id, class_name, data, score = true)
    @logger = Delayed::Worker.logger
    start_time = Time.now

    @logger.info "Start GetUserInformation for a #{class_name}##{object_id} with #{data} at #{start_time.strftime('%H:%M:%S')}..."

    @logger.info 'Fetch object from parse...'

    @object = class_name.constantize.where(id: object_id.to_s).first

    unless @object
      ApplicationController.error(@logger, "Can't find #{class_name}##{object_id}")
      return
    end

    # Initialize industries to an empty array
    @industries = []

    # Initialize original logo we found before uploading it to Cloudinary
    @original_logo = nil

    # Can't Parallelize requests to Pipl and FullContact, because of duplicates networks
    get_pipl(data) if class_name == 'ThoughtLeaders' || class_name == 'MentionedPerson'
    get_fullcontact(data)

    # Flag the object as fetched
    @object['InformationFetched'] = true

    @logger.info "Save object #{class_name}##{object_id} to parse..."
    @object.save

    UpdateScores.perform_later(@object.id, 'ThoughtLeader') if score

    @logger.info "Information found in #{Time.at(Time.now - start_time).strftime('%Mm %Ss')}. Exiting"
  end

  private

  def get_pipl(data)
    @logger.info 'Gather information from Pipl...'

    begin
      # Create a query with available data
      person = Pipl::Person.new
      response = nil

      person.add_field Pipl::Email.new(address: data[:email]) if data[:email]
      person.add_field Pipl::Username.new(content: "#{data[:twitter]}@twitter") if data[:twitter]
      person.add_field Pipl::Username.new(content: "#{data[:facebook]}@facebook") if data[:facebook]

      if data[:name]
        data[:name] = remove_name_title(data[:name])
        names = data[:name].split(' ', 2) # Split first name and last name
        if names.count == 2 && names.first.size > 1 && names.last.size > 1
          person.add_field Pipl::Name.new(first: names.first, last: names.last)
        end
      end

      Retriable.retriable do
        response = Pipl::client.search(person: person)
      end

      # It is a good practice to log the warnings and review them every once in a while.
      if response && response.warnings
        ApplicationController.error(@logger, "Find warnings for #{data} & #{response.warnings}")
      end

      if response && response.person
        results = []

        # Loop through jobs (organisation or employer)
        if response.person.jobs.count >= 1
          response.person.jobs.each do |j|
            name = j.organization || j.title
            if name && results.select{|r| r[:NetworkName] == name }.count <= 0
              results << { NetworkName: name, Industry: j.industry ? clear_name(j.industry) : nil }
            end
          end
        end

        # Loop through educations (university)
        if response.person.educations.count >= 1
          response.person.educations.each do |e|
            if e.display && results.select{|r| r[:NetworkName] == e.display }.count <= 0
              results << { NetworkName: e.display, Industry: nil }
            end
          end
        end

        unless results.empty?
          # Create or retrieve existing Industries
          add_industries(results.select{|r| r[:Industry] }.map{|r| r[:Industry] }.uniq)

          # Create or retrieve existing Networks
          add_networks(results)
        end
      else
        @logger.warn("Can't find person for get_pipl #{data}")
        # ApplicationController.error(@logger, "Can't find person for get_pipl #{data}")
      end
    rescue Exception => e
      @logger.warn("Can't find Information for get_pipl #{data}: #{e.message}")
      # ApplicationController.error(@logger, "Can't find Information for get_pipl #{data}", e)
    end
  end

  def get_fullcontact(data)
    @logger.info 'Gather Information from FullContact...'

    person = nil

    begin
      Retriable.retriable do
        if data[:email]
          person = FullContact.person(email: data[:email])
        elsif data[:twitter]
          person = FullContact.person(twitter: data[:twitter])
        elsif data[:facebook]
          person = FullContact.person(facebookId: data[:facebook])
        end
      end
    rescue Exception => e
      @logger.warn("Can't find information for get_fullcontact #{data}: #{e.message}")
      # ApplicationController.error(@logger, "Can't find information for get_fullcontact #{data}", e)
    end

    if person
      # Add current job position to object
      add_current_job(person) if person.organizations

      # Add extra Information to object
      add_extra_infos(person) if person.social_profiles
    else
      @logger.warn("Can't find person for get_fullcontact #{data}")
      # ApplicationController.error(@logger, "Can't find person for get_fullcontact #{data}")
    end
  end

  def add_current_job(person)
    # Select first organization flagged as primary
    job = person.organizations.select{|o| o['is_primary'] }.first

    if job && job.name
      if @object.class.to_s == 'ThoughtLeaders' || @object.class.to_s == 'MentionedPerson'
        # Search if network already exists
        company = job.name.split('@').last.strip

        # Extract Annotations
        networks = extract_annotations([{ NetworkName: company, Industry: nil }])

        return if networks == false

        if networks.count > 0
          name = networks.first[:NetworkName]
          state = networks.first[:Hidden]
          network = Network.where(NetworkNameLC: name.downcase).first_or_initialize(
              NetworkName: name,
              NetworkNameLC: name.downcase,
              Hidden: state,
              mentions: [],
              mentions_count: 0,
              score: 1,
              identified_by_mention: false
          )

          if network.new_record?
            network.save
            # Add freshly created Network to fetch images
            GetNetworkInformation.perform_now(network.id.to_s, networks.first[:NetworkUrl]) unless state
          end

          @object.array_add_relation('Networks', network.pointer)
          Utils.update_network_score(network)
        end
      end

      # Add job title to object, like "Founder @ Newsworthy.io"
      @object['JobTitle'] = "#{job.title} @ #{job.name}"
    else
      @logger.warn("Can't find job for get_fullcontact")
      # ApplicationController.error(@logger, "Can't find job for get_fullcontact #{data}")
    end
  end

  def add_extra_infos(person)
    # Loop through all available social profiles
    person.social_profiles.each do |p|
      if p.type == 'linkedin'
        @object['LinkedinURL'] = p.url
      end
    end
  end

  def clear_name(name)
    # Titleize only if string contains lowercase chars
    name = name.titleize if name.match(/^[a-z ]*$/)

    # Strip '\', ',' & '.' and trim whitespaces
    name.gsub('\\', '').gsub(',', '').strip
  end

  def add_industries(results)
    begin
      results.each do |r|
        industry = Industry.where(IndustryNameLC: r.downcase).first

        if industry
          @logger.info "Update industry count '#{r}'"

          industry.update(MembersCount: ThoughtLeaderIndustry.where(relatedId: industry.id).count)
        else
          # Create missing Industries and add relation
          @logger.info "Create industry '#{r}' as relation"

          industry = Industry.create({
              IndustryName: r,
              IndustryNameLC: r.downcase,
              IconURL: nil,
              Hidden: false,
              MembersCount: 1
          })

          # Add Industry to array
          @industries << industry

          # Add Industry to Search
          add_object_to_search(industry)
        end

        @object.array_add_relation('Industries', industry.pointer)
      end
    rescue Exception => e
      ApplicationController.error(@logger, "Can't add industries for #{@object.id}", e)
    end
  end

  def add_networks(results)
    begin
      # Retrieve all existing networks

      # Extract Annotations
      results = extract_annotations(results)

      results.each do |r|
        network = Network.where(NetworkNameLC: r[:NetworkName].downcase).first

        if network
          # Add relation for existing networks
          @logger.info "Add existing network '#{r[:NetworkName]}##{network.id}' as relation"

          # Add Network to fetch information if not fetched yet
          GetNetworkInformation.perform_now(network.id.to_s) unless network['InformationFetched']

          @object.array_add_relation('Networks', network.pointer)
        else
          # Create missing networks and add relation
          industry = (r[:Industry] ? @industries.select {|i| i['IndustryName'] == r[:Industry] || i['IndustryNameLC'] == r[:Industry].downcase }.first : nil)

          @logger.info "Create network '#{r[:NetworkName]}' as relation"

          network = Network.create({
              NetworkName: r[:NetworkName],
              NetworkNameLC: r[:NetworkName].downcase,
              Industry: (industry ? industry.pointer : nil),
              identified_by_mention: false,
              Hidden: r[:Hidden],
              mentions: [],
              mentions_count: 0,
              score: 1
          })

          @logger.info "Add new network '#{r[:NetworkName]}##{network.id}' as relation"

          GetNetworkInformation.perform_now(network.id.to_s, r[:NetworkUrl]) unless r[:Hidden]

          @object.array_add_relation('Networks', network.pointer)
        end

        Utils.update_network_score(network)
      end

    rescue Exception => e
      ApplicationController.error(@logger, "Can't add networks for #{@object.id}", e)
    end
  end

  def extract_annotations(results)
    networks = []
    api = Dandelion::API.new(logger: @logger)

    results.each do |r|
      response = api.fetch(r[:NetworkName], {Industry: r[:Industry]})
      networks.concat(response) if response
    end

    networks
  end

  def remove_name_title(name)
    name.gsub(/^Dr\./, '').gsub(/^Pr\./, '').gsub(/^Sen\./, '').strip
  end

  def add_object_to_search(obj)
    @logger.info "Add Industry \"#{obj['IndustryName']}\" to Search Class"

    Search.where(EntityType: 'Industry', EntityName: obj['IndustryName']).first_or_initialize.update(
      {
          EntityId: obj.id,
          EntityType: 'Industry',
          EntityName: obj['IndustryName'],
          EntityNameLC: obj['IndustryName'].downcase,
          EntityMedia: obj['IconURL'],
          EntityHidden: obj['Hidden'],
          EntityCount: obj['MembersCount'],
          Industry: obj.pointer
      }
    )
  end
end
