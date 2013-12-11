require 'rubygems'
require 'bundler/setup'
Bundler.require

class OctostalkerApplication < Sinatra::Base
  set :root,          File.dirname(__FILE__)
  set :assets,        Sprockets::Environment.new(root)
  set :precompile,    [ /\w+\.(?!js|scss).+/, /application.(css|js)$/ ]
  set :assets_prefix, '/assets'
  set :digest_assets, false
  set :assets_path,   File.join(root, assets_prefix)
  set :partial_template_engine, :haml
  set :haml, { :format => :html5 }
  set :server, :puma
  enable :sessions, :logging

  configure do
    %w{javascripts stylesheets images font}.each do |type|
      assets.append_path "assets/#{type}"
    end

    Compass.configuration do |compass|
      compass.project_path = settings.assets_path
      compass.images_dir = 'images'
      compass.output_style = ':expanded'
      compass.relative_assets = true
    end

    Sprockets::Helpers.configure do |config|
      config.environment = assets
      config.prefix      = assets_prefix
      config.digest      = digest_assets
      config.public_path = public_folder
      config.debug       = true
    end

    use OmniAuth::Builder do
      provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: "user:follow"
    end
  end

  error 403 do
    {message:'Sorry, you have to login first.'}.to_json
  end

  get '/' do
    if client
      client.organizations.each do |org|
        org.rels[:avatar].href
      end
      @organizations = client.organizations
      @organizations.map! { |o| organization_hash(o) }

      @friends = get_friends
      @friends.map!{ |u| user_hash(u) }
      haml :logged, layout: :'layouts/application'
    else
      haml :index, layout: :'layouts/application'
    end
  end

  get '/logout' do
    session.clear
    redirect to('/')
  end

  get '/auth/github/callback' do
    session[:auth] ||= {}
    auth = env['omniauth.auth']
    session[:auth][:uid] = auth['uid']
    session[:auth][:token] = auth['credentials']['token']
    avatar = auth[:extra][:raw_info][:avatar_url]
    avatar = avatar + "&s=400" if avatar =~ /.gravatar.com/
    session[:auth][:avatar] = avatar
    redirect to('/')
  end

  post '/friends.do' do
    content_type :json
    client or (return 403)
    follow_users client.followers
    {success: true}.to_json
  end

  get '/organization/:org' do
    client or (return 403)
    org = params[:org]
    org = client.org(org)
    partial :organization, locals: {
      organization: organization_hash(org, true)
    }
  end

  def organization_hash(org, load_members = false)
    avatar = org.rels[:avatar].href
    avatar = avatar + "&s=400" if avatar =~ /.gravatar.com/
    members = []

    if load_members
      members = client.organization_members(org.login, per_page: 16, auto_paginate: false)[0..15]
      members.map!{ |u| user_hash(u) }
    end

    { avatar: avatar,
      login: org.login,
      members: members
    }
  end


  def user_hash(user)
    {
      avatar: user.rels[:avatar].href,
      follows: false,
      login: user.login,
    }
  end

  post '/organization.do' do
    content_type :json
    client or (return 403)

    begin
      org = params[:org]
      follow_users client.organization_members(org)
    rescue Octokit::NotFound
      status 404
      return {message: 'Organization not found'}.to_json
    end
    {success: true}.to_json
  end

  post '/me.do' do
    content_type :json
    client or (return 403)
    {success: client.follow('arthurnn')}.to_json
  end

  def client
    return nil unless session[:auth]
    @client ||= Octokit::Client.new(access_token: session[:auth][:token])
  end

  def follow_users(users)
    users.each do |member|
      login = member.login
      next if login == client.login
      client.follow(login)
    end
  end

  def get_friends
    friends = client.followers(client.login, per_page: 999, auto_paginate: false)
    ids_of_users_being_followed = client.following(client.login, per_page: 999).map { |f| f.id }
    friends.reject { |f| ids_of_users_being_followed.include? f.id }
  end

  register Sinatra::Partial
  helpers do
    include Sprockets::Helpers

    def current_user
      session[:auth]
    end
  end
end
