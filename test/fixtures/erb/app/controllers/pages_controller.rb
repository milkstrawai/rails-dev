class PagesController < ActionController::Base
  def show
    cookies[:visit] = "erb"
  end
end
