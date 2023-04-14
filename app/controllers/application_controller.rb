class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  # protect_from_forgery with: :exception

  def render_404
    head(:not_found)
  end

  def redirect_nwy
    redirect_to (Rails.env == 'production' ? 'http://getmaven.io' : 'http://beta.nwy:3000/'), status: :permanent_redirect
  end

  def self.error(logger, text, e = nil)
    if e
      logger.warn "#{text}: #{e.class} - #{e.message}"
    else
      logger.warn text
      e = Exception.new(text)
    end
    Airbrake.notify(e, text: text)
    false
  end
end
