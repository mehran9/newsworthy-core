Rails.application.routes.draw do
  constraints domain: %w(mvn.one nwy.io shr.nwy) do
    get '/:id', to: 'articles#show'
    get '/r/:id', to: 'users#redirect'
    match '/' => 'application#redirect_nwy', via: :all
    match '*path', to: 'application#redirect_nwy', via: :all
  end

  constraints domain: %w(getmaven.io newsworthy.io beta.nwy) do
    get '/' => 'users#new', as: :homepage
    match 'users/create' => 'users#create', via: :post
    get '/refer-a-friend/:id' => 'users#refer', as: :refer
    get '/privacy-policy' => 'users#policy', as: :policy
    get '/terms-of-use' => 'users#terms', as: :terms
    get '/auth/:provider/callback' => 'users#callback'
    match '*path', to: 'application#redirect_nwy', via: :all
  end
end
