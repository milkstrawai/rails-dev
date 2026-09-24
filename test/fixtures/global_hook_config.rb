RailsDev.configure do |config|
  config.before_start { |events| events << :global }
  config.after_ready { |events| events << :global_ready }
end
