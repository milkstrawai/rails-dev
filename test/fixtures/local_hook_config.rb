RailsDev.configure do |config|
  config.before_start.clear
  config.before_start { |events| events << :local }
end
