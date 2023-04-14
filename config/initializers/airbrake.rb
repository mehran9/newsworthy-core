Airbrake.configure do |config|
  config.host = 'https://powerful-lowlands-71895.herokuapp.com'
  config.project_id = 1 # required, but any positive integer works
  config.project_key = '6d34c35d9c77ff05c8759b2ab4599e5e'
  config.environment = Rails.env
  config.ignore_environments = %w(development test)
end

Airbrake.add_filter do |notice|
  errors = %w(MultiJson::LoadError ArgumentError EOFError Errno::ENOENT SystemExit MetaInspector::RequestError MetaInspector::TimeoutError Amazon::RequestError RestClient::RequestTimeout RestC​lient​::Gat​ewayT​imeou​t RestC​lient​::Ser​viceU​navai​lable Errno​::ENO​ENT Cocaine::ExitStatusError Net::ReadTimeout Dandelionapi::BadResponse)
  if notice[:errors].any? { |error| errors.include?(error[:type]) }
    notice.ignore!
  end
end
