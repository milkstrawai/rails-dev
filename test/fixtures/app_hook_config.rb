RailsDev.configure do |config|
  config.before_start { |events| events << :app }
end
