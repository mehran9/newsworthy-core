class UsersController < ApplicationController
  before_action :check_user, only: :refer

  def new
  end

  def create
    unless params[:email] || params[:password]
      render text: 'Missing parameters', status: :unprocessable_entity and return
    end

    user = classic_login
    return unless user

    render text: refer_path(user['objectId'])
  end

  def fb_login
    render layout: false
  end

  def refer
    @title = 'Maven - Thank you for Signing Up'

    if request.env['SERVER_NAME'] == 'beta.nwy'
      @share_url = "http://shr.nwy:3000/r/#{@user['UserObjectID'].id}"
    elsif request.env['SERVER_NAME'] == 'beta.getmaven.io'
      @share_url = "http://b.mvn.one/r/#{@user['UserObjectID'].id}"
    else
      @share_url = "http://mvn.one/r/#{@user['UserObjectID'].id}"
    end
  end

  def redirect
    if request.env['SERVER_NAME'] == 'shr.nwy'
      url = 'http://beta.nwy:3000'
    elsif request.env['SERVER_NAME'] == 'b.mvn.one'
      url = 'http://beta.getmaven.io'
    else
      url = 'http://getmaven.io'
    end

    redirect_to "#{url}#{homepage_path(r: params[:id])}", status: 301
  end

  def callback
    auth = request.env['omniauth.auth']
    redirect_to homepage_path(r: params[:r]), alert: "Invalid credentials while connecting with #{auth.provider} oauth" unless auth

    params[:r] = request.env['omniauth.params']['r'] unless request.env['omniauth.params']['r'].empty?

    if auth.provider == 'twitter'
      user = twitter_login(auth)
    else
      user = facebook_login(auth)
    end

    if user
      redirect_to refer_path(user['objectId'])
    else
      return
    end
  end

  def policy
    @title = 'Maven - Privacy Policy'
  end

  def terms
    @title = 'Maven - Terms of Use'
  end

  private

  def classic_login
    unless params[:email] =~ /\A(\S+)@(.+)\.(\S+)\z/i
      render text: 'Invalid email address', status: :unprocessable_entity and return false
    end
    user = User.where(email: params[:email]).first
    if user
      begin
        Parse::User.authenticate(user['username'], params[:password])
      rescue Exception => e
        unless e.message == '101: invalid login parameters'
          Airbrake.notify(e, user: params[:email])
        end
        render text: 'Invalid credentials', status: :unprocessable_entity and return false
      end
    else
      user = nil
      begin
        user = User.create(
            {
                email: params[:email],
                password: params[:password],
                username: params[:email],
                BetaAccess: false
            }
        )
      rescue Exception => e
        Airbrake.notify(e, user: params[:email])
        render text: 'Invalid parameters', status: :unprocessable_entity and return false
      end

      # Add a job in cue to get informations about the user
      GetUserInformation.perform_later(user.id.to_s, 'User', {email: user['email']})

      add_user_to_cue(user)
    end
    user
  end

  def facebook_login(auth)
    user = nil
    begin
      unless auth.info.email
        redirect_to homepage_path(r: params[:r]), alert: 'Your Facebook privacy settings prevent us from capturing your email address. Please sign up instead using your email address above'
        return false
      end

      Retriable.retriable do
        user = Parse::Query.new('_User').tap do |q|
          q.eq('email', auth.info.email)
        end.get.first
      end

      unless user
        user = Parse::Object.new('_User',
           {
               email: auth.info.email,
               password: SecureRandom.hex,
               username: auth.info.email,
               FullName: auth.info.name,
               SocialProfileAvatarURL: auth.info.image,
               BetaAccess: false
           }
        )
        Retriable.retriable do
          user.save
        end

        add_user_to_cue(user)
      end

      user['authData'] =  { facebook: {
          id: auth.uid,
          access_token: auth.credentials.token,
          expiration_date: Parse::Date.new(Time.at(auth.credentials.expires_at))
      }}
      Retriable.retriable do
        user.save
      end

      # Add a job in cue to get informations about the user
      GetUserInformation.perform_later(user.id.to_s, 'User',
                                                                 {
              email: user['email'],
              name: user['FullName']
              # facebook: auth.uid # Facebook removed as we only get an App Scoped ID of the user, not real user id
          }
      )

      return user
    rescue Exception => e
      Airbrake.notify(e)
      if e.class == Parse::ParseProtocolError && e.message =~ /^208:/
        text = 'Please sign in with the social account you have previously connected with'
      else
        text = 'Please check your Facebook permissions for the Maven app'
      end
      redirect_to homepage_path(r: params[:r]), alert: text
      return false
    end
  end

  def twitter_login(auth)
    user = nil
    begin
      unless auth.info.email
        redirect_to homepage_path(r: params[:r]), alert: 'Your Twitter privacy settings prevent us from capturing your email address. Please sign up instead using your email address above'
        return false
      end

      Retriable.retriable do
        user = Parse::Query.new('_User').tap do |q|
          q.eq('email', auth.info.email)
        end.get.first
      end

      unless user
        user = Parse::Object.new('_User',
                                 {
                                     email: auth.info.email,
                                     password: SecureRandom.hex,
                                     username: auth.info.nickname,
                                     FullName: auth.info.name,
                                     SocialProfileAvatarURL: auth.info.image,
                                     BetaAccess: false
                                 }
        )
        Retriable.retriable do
          user.save
        end

        add_user_to_cue(user)
      end

      user['authData'] = {} unless user['authData']

      user['authData'] =  { twitter: {
          id: auth.uid,
          screen_name: auth.info.nickname,
          consumer_key: Settings.website.twitter.consumer_key,
          consumer_secret: Settings.website.twitter.consumer_secret,
          auth_token: auth.credentials.token,
          auth_token_secret: auth.credentials.secret
      }}

      Retriable.retriable do
        user.save
      end

      # Add a job in cue to get informations about the user
      GetUserInformation.perform_later(user.id.to_s, 'User',
                                                                 {
              email: user['email'],
              name: user['FullName'],
              twitter: auth.info.nickname
          }
      )

      return user
    rescue Exception => e
      Airbrake.notify(e)
      if e.class == Parse::ParseProtocolError && e.message =~ /^208:/
        text = 'Please sign in with the social account you have previously connected with'
      else
        text = 'Please check your Twitter permissions for the Maven app'
      end
      redirect_to homepage_path(r: params[:r]), alert: text
      return false
    end
  end

  def add_user_to_cue(user)
    count = nil
    Retriable.retriable do
      count = Parse::Query.new('Prelauncher').tap do |q|
        q.limit = 0
        q.count
      end.get
    end
    return unless count

    groups = []
    Retriable.retriable do
      groups = Parse::Query.new('BetaGroups').tap do |q|
        q.order_by = 'shares'
      end.get
    end

    pre = Parse::Object.new('Prelauncher',
      {
          EmailAddress: user['email'],
          ReferralCount: 0,
          UserObjectID: user.pointer,
          BetaGroup: groups.first['allocation']
      }
    )

    groups.first['allocation'] = Parse::Increment.new(1)
    Retriable.retriable do
      groups.first.save
    end

    if params[:r] && params[:r] != user['objectId']
      ref = nil
      pointer = Parse::Pointer.new({'className' => '_User', 'objectId' => params[:r]})
      Retriable.retriable do
        ref = Parse::Query.new('Prelauncher').tap do |q|
          q.eq('UserObjectID', pointer)
        end.get.first
      end

      if ref
        new_grp = groups.select{|g| ref['ReferralCount'] + 1 >= g['shares'] }.last
        old_grp = groups.select{|g| ref['ReferralCount'] >= g['shares']}.last

        if new_grp != old_grp && new_grp['allocation'] <= new_grp['offset']
          ref['BetaGroup'] = new_grp['allocation']
          new_grp['allocation'] = Parse::Increment.new(1)
          Retriable.retriable do
            new_grp.save
          end
          unless old_grp['shares'] == 0
            old_grp['allocation'] = Parse::Increment.new(-1)
            Retriable.retriable do
              old_grp.save
            end
          end
        end

        pre['ReferringUser'] = pointer
        ref['ReferralCount'] = Parse::Increment.new(1)
        Retriable.retriable do
          ref.save
        end
      end
    end

    Retriable.retriable do
      pre.save
    end

    # Add a job in cue to add user to mailing list
    AddSubscriber.set(queue: :low_priority).perform_later(user['email'])
  end

  def check_user
    @user = false

    Retriable.retriable do
      @user = Parse::Query.new('Prelauncher').tap do |q|
        q.eq('UserObjectID', Parse::Pointer.new({'className' => '_User', 'objectId' => params[:id]}))
      end.get.first
    end

    redirect_to homepage_path(r: params[:r]) unless @user
  end
end
