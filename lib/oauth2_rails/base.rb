module Oauth2Rails
  class Base

    def initialize(options = {})
      raise Oauth2Rails::Errors::InvalidArgument, 'Must instantiate oauth_id and oauth_secret' if options[:oauth_id].nil? && options[:oauth_secret].nil?
      @oauth_id       = options[:oauth_id]       || '229MB3'
      @oauth_secret   = options[:oauth_secret]   || '63b9c42d78061f6eec4a29e206341dc5'
      @redirect_uri   = options[:redirect_uri]   || 'http://localhost:3000/oauth2_callbacks/fitbit'
      @authorize_site = options[:authorize_site] || 'https://www.fitbit.com'
      @authorize_path = options[:authorize_path] || '/oauth2/authorize'
      @api_site       = options[:api_site]       || 'https://api.fitbit.com'
      @token_path     = options[:token_path]     || '/oauth2/token'
      @scope          = options[:scope]          || 'heartrate'
    end

    def connection(url)
      Faraday.new(url: url) do |faraday|
        faraday.request  :url_encoded
        faraday.response :logger
        faraday.adapter  Faraday.default_adapter
      end
    end

    def call(action, destination, options = {})
      user = options[:user]
      site = options[:site] || @api_site

      if user
        auth_header = "Bearer #{user}"
      else
        encoded = Base64.strict_encode64("#{@oauth_id}:#{@oauth_secret}")
        auth_header = "Basic #{encoded}"
      end

      response = connection(site).send(action) do |req|
        req.url destination
        req.headers['Content-Type']   = 'application/x-www-form-urlencoded'
        req.headers['Authorization']  = auth_header
        req.body = options[:body]
      end

      case response.status
        when 400 ; raise Oauth2Rails::Errors::BadRequest,      "400 #{get_error_message(response)}"
        when 404 ; raise Oauth2Rails::Errors::NotFound,        "404 #{get_error_message(response)}"
        when 409 ; raise Oauth2Rails::Errors::Conflict,        "409 #{get_error_message(response)}"
        when 500 ; raise Oauth2Rails::Errors::InternalServer,  "500 #{get_error_message(response)}"
        when 502 ; raise Oauth2Rails::Errors::BadGateway,      "502 #{get_error_message(response)}"
        when 401 ; raise Oauth2Rails::Errors::Unauthorized,    "401 #{get_error_message(response)}"
        else ; return Response.new(response)
      end

    end

    def api_call(user, destination)
      begin
        call(:get, destination, user: user.access_token)
      rescue FitbitOauth2::Errors::Unauthorized
        refresh(user)
        call(:get, destination, user: user.access_token)
      end
    end

    def refresh(user)
      response = call(:post, "#{@token_path}?grant_type=refresh_token&refresh_token=#{user.refresh_token}")
      user.update!(access_token: response.access_token, refresh_token: response.refresh_token)
    end

  end
end