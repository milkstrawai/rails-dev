RailsDev.configure do |config|
  config.around_run do |_run, continue|
    continue.call
  rescue RailsDev::Error
    nil
  end
end
