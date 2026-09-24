bind "tcp://127.0.0.1:#{ENV.fetch('PORT', 3000)}"
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
