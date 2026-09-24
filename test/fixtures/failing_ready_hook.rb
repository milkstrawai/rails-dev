RailsDev.configure do |config|
  config.after_ready { raise "Ready hook failed" }
end
