require 'pipl'

Pipl.configure do |c|
  c.api_key = Settings.pipl.api_key
  c.show_sources = 'false'
  c.minimum_probability = 0.9
  c.minimum_match = 0.5
  c.strict_validation = true
  c.hide_sponsored = true
end
