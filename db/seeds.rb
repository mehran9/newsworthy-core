# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

# use admin
# db.createUser( {
#                    user: "maven_staging",
#                    pwd: "49b6d465d2e4739e0b0fe41388e258d24e7d30f3114a9cac5ecf1a74648604ee",
#                    roles: [ { role: "readWrite", db: "maven_staging" } ]
#                });
# db.createUser( {
#                    user: "root",
#                    pwd: "6a49454b8386a0b5e4a89708444c7c42d28caa7a20e30b75b7f8479017f44cb0",
#                    roles: [ { role: "root", db: "admin" } ]
#                });

# db.getCollection('Article').aggregate(
#     { $group : {_id : "$url", total : { $sum : 1 } } },
#     { $match : { total : { $gte : 2 } } }
# );
#
# db.getCollection('Article').aggregate(
#     { $group : {_id : "$md5_content", total : { $sum : 1 } } },
#     { $match : { total : { $gte : 2 } } }
# );
#
# db.getCollection('ThoughtLeaders').aggregate(
#     { $group : {_id : "$twitter_id", total : { $sum : 1 } } },
#     { $match : { total : { $gte : 2 } } }
# );
#
# db.getCollection('MentionedPerson').aggregate(
#     { $group : {_id : "$twitter_id", total : { $sum : 1 } } },
#     { $match : { total : { $gte : 2 } } }
# );
#
#
# db.getCollection('_Join:mentions:Article').aggregate(
#     { $group : {_id : "$twitter_id", total : { $sum : 1 } } },
#     { $match : { total : { $gte : 2 } } }
# );

# db.auth('maven_production', 'e876c073ba54f5c5bf5b6bcba301ed4c80f02bb4c6508bab0794f6d61d05282b')
#
# db.Mention.find().forEach( function(x){db.Mention_copy.insert(x)} );
# db.Article.find().forEach( function(x){db.Article_copy.insert(x)} );
# db.IndustryTweets.find().forEach( function(x){db.IndustryTweets_copy.insert(x)} );
# db.NetworkTweets.find().forEach( function(x){db.NetworkTweets_copy.insert(x)} );
# db.MentionIndustryTweets.find().forEach( function(x){db.MentionIndustryTweets_copy.insert(x)} );
# db.MentionNetworkTweets.find().forEach( function(x){db.MentionNetworkTweets_copy.insert(x)} );
#
# db.getCollection('Article').remove({})
# db.getCollection('BannedPublication').remove({})
# db.getCollection('Industry').remove({})
# db.getCollection('IndustryTweets').remove({})
# db.getCollection('Mention').remove({})
# db.getCollection('MentionIndustryTweets').remove({})
# db.getCollection('MentionNetworkTweets').remove({})
# db.getCollection('MentionedPerson').remove({})
# db.getCollection('Network').remove({})
# db.getCollection('NetworkTweets').remove({})
# db.getCollection('Publisher').remove({})
# db.getCollection('Search').remove({})
# db.getCollection('Streamer').remove({})
# db.getCollection('ThoughtLeaders').remove({})
# db.getCollection('_Join:articles:Mention').remove({})
# db.getCollection('_Join:Industries:_User').remove({})
# db.getCollection('_Join:network_mention:Article').remove({})
# db.getCollection('_Join:Networks:_User').remove({})
# db.getCollection('_Join:Industries:Article').remove({})
# db.getCollection('_Join:mentions:Article').remove({})
# db.getCollection('_Join:Networks:Article').remove({})
# db.getCollection('_Join:ThoughtLeaders:Article').remove({})
# db.getCollection('_Join:Industries:Mention').remove({})
# db.getCollection('_Join:mentions_articles:MentionIndustryTweets').remove({})
# db.getCollection('_Join:Networks:Mention').remove({})
# db.getCollection('_Join:tl_mention:Article').remove({})
# db.getCollection('_Join:Industries:MentionedPerson').remove({})
# db.getCollection('_Join:mentions_articles:MentionNetworkTweets').remove({})
# db.getCollection('_Join:Networks:MentionedPerson').remove({})
# db.getCollection('_Join:users:_Role').remove({})
# db.getCollection('_Join:Industries:ThoughtLeaders').remove({})
# db.getCollection('_Join:mp_mention:Article').remove({})
# db.getCollection('_Join:Networks:ThoughtLeaders').remove({})
#
BannedPublication.find_or_create_by({ name: 'facebook.com'})
BannedPublication.find_or_create_by({ name: 'growthhackers.com'})
BannedPublication.find_or_create_by({ name: 'paper.li'})
BannedPublication.find_or_create_by({ name: 'networks.h-net.org'})
BannedPublication.find_or_create_by({ name: 'cmail1.com'})
BannedPublication.find_or_create_by({ name: 'commun.it'})
BannedPublication.find_or_create_by({ name: 'storify.com'})
BannedPublication.find_or_create_by({ name: 'campaign-archive1.com'})
BannedPublication.find_or_create_by({ name: 'us8.campaign-archive1.com'})
BannedPublication.find_or_create_by({ name: 'twibbon.com'})
BannedPublication.find_or_create_by({ name: 'secure-nikeplus.nike.com'})
BannedPublication.find_or_create_by({ name: 'twitter.com'})
BannedPublication.find_or_create_by({ name: 'thecooperreview.com'})
BannedPublication.find_or_create_by({ name: 'vrfocus.com'})
BannedPublication.find_or_create_by({ name: 'hunterwalk.com'})
BannedPublication.find_or_create_by({ name: 'nextdraft.com'})
BannedPublication.find_or_create_by({ name: 'talkingpointsmemo.com'})
BannedPublication.find_or_create_by({ name: 'parenting.blogs.nytimes.com'})
BannedPublication.find_or_create_by({ name: 'blog.poynt.com'})
BannedPublication.find_or_create_by({ name: 'finsmes.com'})
BannedPublication.find_or_create_by({ name: 'neurosciencenews.com'})
BannedPublication.find_or_create_by({ name: 'credoaction.com'})
BannedPublication.find_or_create_by({ name: 'shareable.net'})
BannedPublication.find_or_create_by({ name: 'fiftyfiveandfive.com'})
BannedPublication.find_or_create_by({ name: 'utilitydive.com'})
BannedPublication.find_or_create_by({ name: 'ajnyc.wordpress.com'})
BannedPublication.find_or_create_by({ name: 'aspennewvoices.org'})
BannedPublication.find_or_create_by({ name: 'onthemedia.org'})
BannedPublication.find_or_create_by({ name: 'info.changetip.com'})
BannedPublication.find_or_create_by({ name: 'brandingmagazine.com'})
BannedPublication.find_or_create_by({ name: 'orlandosentinel.com'})
BannedPublication.find_or_create_by({ name: 'digitaljournal.com'})
BannedPublication.find_or_create_by({ name: 'auth0.com'})
BannedPublication.find_or_create_by({ name: 'spur.org'})
BannedPublication.find_or_create_by({ name: 'revolution.com'})
BannedPublication.find_or_create_by({ name: 'blog.driftt.com'})
BannedPublication.find_or_create_by({ name: 'goldderby.com'})
BannedPublication.find_or_create_by({ name: 'seedepth.com'})
BannedPublication.find_or_create_by({ name: 'lp2dot0.com'})
BannedPublication.find_or_create_by({ name: 'all-comic.com'})
BannedPublication.find_or_create_by({ name: 'relevance.com'})
BannedPublication.find_or_create_by({ name: 'success.com'})
BannedPublication.find_or_create_by({ name: 'hackbrightacademy.com'})
BannedPublication.find_or_create_by({ name: 'ilikekillnerds.com'})
BannedPublication.find_or_create_by({ name: 'tech.co'})
BannedPublication.find_or_create_by({ name: 'wistia.com'})
BannedPublication.find_or_create_by({ name: 'paulgraham.com'})
BannedPublication.find_or_create_by({ name: 'tonyconrad.wordpress.com'})
BannedPublication.find_or_create_by({ name: 'electrek.co'})
BannedPublication.find_or_create_by({ name: 'wikipedia.org'})
BannedPublication.find_or_create_by({ name: 'linkis.com'})
BannedPublication.find_or_create_by({ name: 'youtu.be'})
BannedPublication.find_or_create_by({ name: 'vine.co'})
BannedPublication.find_or_create_by({ name: 'twimg.com'})
BannedPublication.find_or_create_by({ name: 'instagram.com'})
BannedPublication.find_or_create_by({ name: 'youtube.com'})
BannedPublication.find_or_create_by({ name: 'vimeo.com'})
BannedPublication.find_or_create_by({ name: 'dailymotion.com'})
BannedPublication.find_or_create_by({ name: 'kickstarter.com'})

# mentions = [
#     'MI6',
#     'Michelin',
#     'Honda',
#     'Virgin',
#     'Napster',
#     'H&M',
#     'Bose',
#     'Zipcar',
#     'Federal Reserve',
#     'Hanson',
#     'Chicago Tribune',
#     'TransCanada',
#     'Suzuki',
#     'Fatah',
#     'TripAdvisor',
#     'Citroën',
#     'Community',
#     'Disney',
#     'Casey Neistat',
#     'NBA',
#     'Amazon.com',
#     'Motorola',
#     'Malala Fund',
#     'Macbeth',
#     'Audi',
#     'World of Warcraft',
#     'Brexit',
#     'Power',
#     'Riot Games',
#     'Viacom',
#     'Bloomberg',
#     'NASCAR',
#     'Siri',
#     'Fox News',
#     'Ericsson',
#     'SolarCity',
#     'Facebook',
#     'SoundCloud',
#     'CIA',
#     'Airbus',
#     'Armani',
#     'Catalyst',
#     'David',
#     'Sony',
#     'CBS',
#     'Peter Thiel',
#     'United States',
#     'European Commission',
#     'Metro',
#     'FedEx',
#     'Taylor Wimpey',
#     'Estonia',
#     'Rolex',
#     'Alexa',
#     'Life',
#     'National Football League',
#     'The New York Times',
#     'NBC',
#     'BMW',
#     'SoftBank',
#     'Goldman Sachs',
#     'Forbes',
#     'YouTube',
#     'Wikipedia',
#     'BBC',
#     'ABC',
#     'Heineken',
#     'Gillette',
#     'TNT',
#     'Hank Green',
#     'Samy',
#     'FBI',
#     'DeNA',
#     'Burns',
#     'Orange',
#     'Bitcoin',
#     'Lockheed Martin',
#     'Netflix',
#     'Theranos',
#     'Chelsea',
#     'USA Today',
#     'World Bank',
#     'Twitter',
#     'PayPal',
#     'Free',
#     'Mary Poppins',
#     'Chase',
#     'Microsoft',
#     'Google',
#     'Uber',
#     'The Washington Post',
#     'Dell',
#     'Hyundai',
#     'King',
#     'Gallup',
#     'John',
#     'Deloitte',
#     'Ku Klux Klan',
#     'Google Maps',
#     'UN',
#     'William Hill',
#     'LinkedIn',
#     'Orbitz',
#     'Amazon Web Services',
#     'WikiLeaks',
#     'BuzzFeed',
#     'HTC',
#     "Christie's",
#     'Gawker',
#     'Chuck',
#     'Shutterstock',
#     'Merrill Lynch',
#     'Travis',
#     'Mitsubishi',
#     'Telkom',
#     'Bentley',
#     'Gold',
#     'Outlook',
#     'Chevron',
#     'Unilever',
#     'Communist Party',
#     'Marlboro',
#     'Spotify',
#     'New York Yankees',
#     'Rona',
#     'WhatsApp',
#     'Kansas City Royals',
#     'HBO',
#     'Penguin Random House',
#     'Bernie',
#     'Sears',
#     'Cincinnati Reds',
#     'Financial Times',
#     'Funai',
#     'Novo Nordisk',
#     'CNN',
#     'Yammer',
#     'BitTorrent',
#     'Airbnb',
#     'Nissan',
#     'Finch',
#     'Pirelli',
#     'Raytheon',
#     'Love',
#     'Flipkart',
#     'AT&T',
#     'American Apparel',
#     'Emery',
#     'FDI',
#     'Samsung',
#     'Cadillac',
#     'James',
#     'Super Mario',
#     'Secret Service',
#     'YouGov',
#     'Cleveland Indians',
#     'Philips',
#     'Best Buy',
#     'Glu Mobile',
#     'Sun Microsystems',
#     'Morgan Stanley',
#     'Hubble',
#     'Amadeus',
#     'Peugeot',
#     'Norton',
#     'MTV'
# ]
#
# t = []
# mentions.each do |m|
#   Mention.where(name: m).all.each do |m2 |
#     if Mention.where(name: m, type: m2.type).count > 1
#       t << m unless t.include?(m)
#     end
#   end
# end
#
# t = ["Casey Neistat", "Amazon.com", "Facebook", "Peter Thiel", "National Football League", "The New York Times", "YouTube", "ABC", "Hank Green", "Burns", "Netflix", "Twitter", "Microsoft", "John", "UN", "Spotify", "HBO", "Bernie", "Samsung"]
