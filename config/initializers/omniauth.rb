Rails.application.config.middleware.use OmniAuth::Builder do
  provider :twitter, Settings.website.twitter.consumer_key, Settings.website.twitter.consumer_secret, image_size: 'original'
  provider :facebook, Settings.website.facebook.application_id, Settings.website.facebook.application_secret,
           scope: 'email', info_fields: 'email,name,picture', image_size: {width: 225, height: 225}
end
