require 'cgi'
require 'json'
require 'net/https'
require 'oauth'
require 'uri'

module Lokka
  module SignInWithTwitter
    def self.registered(app)
      # Override to add a login button
      app.get '/admin/login' do
        haml :'plugin/lokka-sign_in_with_twitter/views/login', layout: false
      end

      app.get '/sign_in_with_twitter' do
        request_token = sign_in_with_twitter_consumer.get_request_token(
          oauth_callback: to('/sign_in_with_twitter/callback')
        )
        session[:request_token_secret] = request_token.secret
        url = "https://api.twitter.com/oauth/authenticate?oauth_token="
        redirect url + CGI.escape(request_token.token)
      end

      app.get '/sign_in_with_twitter/callback' do
        access_token = OAuth::RequestToken.new(
          sign_in_with_twitter_consumer,
          params[:oauth_token],
          session[:request_token_secret]
        ).get_access_token(oauth_verifier: params[:oauth_verifier])
        session[:request_token_secret] = nil
        user = sign_in_with_twitter_find(access_token.params['user_id'])
        if user
          session[:user] = user.to_i
          flash[:notice] = t('logged_in_successfully')
          if session[:return_to]
            redirect_url = session[:return_to]
            session[:return_to] = false
            redirect redirect_url
          else
            redirect to('/admin/')
          end
        else
          @login_failed = true
          haml :'plugin/lokka-sign_in_with_twitter/views/login', layout: false
        end
      end

      app.get '/admin/plugins/sign_in_with_twitter' do
        haml :'plugin/lokka-sign_in_with_twitter/views/index', layout: :'admin/layout'
      end

      app.post '/admin/plugins/sign_in_with_twitter' do
        Option.sign_in_with_twitter_ckey = params['consumer_key']
        Option.sign_in_with_twitter_csec = params['consumer_secret']
        flash[:notice] = 'Updated consumer settings.'
        redirect to('/admin/plugins/sign_in_with_twitter')
      end

      app.post '/admin/plugins/sign_in_with_twitter/add_user' do
        # Get a user object from Twitter
        query = '?screen_name=' + CGI.escape(params[:username].gsub(/\W/, ''))
        user = sign_in_with_twitter_get('/1.1/users/show.json' + query)

        # Check if the user already exists
        if sign_in_with_twitter_find(user['id_str'])
          flash[:notice] = 'Sorry, this user has already been associated'
          redirect to('/admin/plugins/sign_in_with_twitter')
        end

        # Update record
        ids = sign_in_with_twitter_ids
        ids[user['id_str']] =  "@#{user['screen_name']}"
        sign_in_with_twitter_ids_update(ids)

        flash[:notice] = "Added @#{user['screen_name']}"
        redirect to('/admin/plugins/sign_in_with_twitter')
      end

      app.post '/admin/plugins/sign_in_with_twitter/delete_user' do
        ids = sign_in_with_twitter_ids
        deleted = ids.delete(params[:twitter_id])
        sign_in_with_twitter_ids_update(ids)
        flash[:notice] = "Removed a user (#{deleted})"
        redirect to('/admin/plugins/sign_in_with_twitter')
      end

      app.post '/admin/plugins/sign_in_with_twitter/update_comment' do
        ids = sign_in_with_twitter_ids
        ids[params[:twitter_id]] = params[:t_comment]
        sign_in_with_twitter_ids_update(ids)
        flash[:notice] = 'Updated comment'
        redirect to('/admin/plugins/sign_in_with_twitter')
      end

      app.helpers do
        def sign_in_with_twitter_consumer
          @sign_in_with_twitter_consumer ||= OAuth::Consumer.new(
            Option.sign_in_with_twitter_ckey,
            Option.sign_in_with_twitter_csec,
            site: 'https://api.twitter.com'
          )
        end

        def sign_in_with_twitter_bearer_token
          if @sign_in_with_twitter_bearer_token
            return @sign_in_with_twitter_bearer_token
          end
          consumer = sign_in_with_twitter_consumer
          auth = "#{consumer.key}:#{consumer.secret}"
          uri = URI("https://#{auth}@api.twitter.com/oauth2/token")
          resp = Net::HTTP.post_form(uri, {grant_type: :client_credentials})
          access_token = JSON.parse(resp.body)['access_token']
          @sign_in_with_twitter_bearer_token = access_token
        end

        def sign_in_with_twitter_find(twitter_id)
          twitter_id = twitter_id.to_s
          sign_in_with_twitter_ids_all.each do |lokka_id, twitter_ids|
            return lokka_id if twitter_ids.keys.include?(twitter_id)
          end
          nil
        end

        def sign_in_with_twitter_get(path)
          b_token = sign_in_with_twitter_bearer_token
          http = Net::HTTP.new('api.twitter.com', '443')
          http.use_ssl = true
          http.start
          req = Net::HTTP::Get.new(path, 'Authorization' => "Bearer #{b_token}")
          resp = http.request(req)
          http.finish
          JSON.parse(resp.body)
        end

        def sign_in_with_twitter_ids
          sign_in_with_twitter_ids_all[session[:user].to_s] || {}
        end

        def sign_in_with_twitter_ids_update(body)
          all = sign_in_with_twitter_ids_all
          all[session[:user].to_s] = body
          sign_in_with_twitter_ids_all_update(all)
        end

        def sign_in_with_twitter_ids_all
          JSON.load(Option.sign_in_with_twitter_ids || '{}') rescue {}
        end

        def sign_in_with_twitter_ids_all_update(body)
          Option.sign_in_with_twitter_ids = JSON.dump(body)
        end
      end
    end
  end
end
