Amazon::Awis.configure do |options|
  options[:aws_access_key_id] = Settings.aws.access_key_id
  options[:aws_secret_key] = Settings.aws.secret_key
  options[:responsegroup] = 'RankByCountry,Categories'
end
