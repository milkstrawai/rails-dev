# frozen_string_literal: true

require "test_helper"
require "rails_dev/cookies"
require "rack"

class CookiesTest < Minitest::Test
  def test_filters_incoming_cookies
    app = ->(env) { [200, {}, [Rack::Request.new(env).cookies.to_json]] }
    middleware = RailsDev::Cookies.new(app, prefix: "first-")
    cookies = "first-session=one; second-session=two; session=old; first-XSRF-TOKEN=token"
    _, _, body = middleware.call("HTTP_COOKIE" => cookies)

    assert_equal({ "session" => "one", "XSRF-TOKEN" => "token" }, JSON.parse(body.join))
  end

  def test_preserves_outgoing_cookie_attributes
    values = ["session=one; path=/; secure; httponly; samesite=lax", "XSRF-TOKEN=two; path=/"]
    app = ->(_env) { [200, { "set-cookie" => values }, []] }
    _, headers, = RailsDev::Cookies.new(app, prefix: "first-").call({})

    assert_equal ["first-session=one; path=/; secure; httponly; samesite=lax", "first-XSRF-TOKEN=two; path=/"],
                 headers.fetch("set-cookie")
  end

  def test_expires_only_the_current_cookie
    cookie = "remember_user_token=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT"
    app = ->(_env) { [200, { "set-cookie" => cookie }, []] }
    _, headers, = RailsDev::Cookies.new(app, prefix: "second-").call({})

    assert_equal ["second-#{cookie}"], headers.fetch("set-cookie")
  end

  def test_keeps_responses_without_cookies
    response = [200, { "content-type" => "text/plain" }, ["ok"]]
    app = ->(_env) { response }

    assert_equal response, RailsDev::Cookies.new(app, prefix: "first-").call({})
  end
end
