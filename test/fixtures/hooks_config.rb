require "rbconfig"

record = lambda do |name, run|
  File.open(run.env.fetch("TEST_EVENTS"), "a") do |file|
    file.puts JSON.generate(event: "hook", name: name, pid: Process.pid, root: run.root,
                           runtime: run.runtime, runtime_exists: File.directory?(run.runtime),
                           url: run.url, vite_url: run.url(:js), pgport: run.env["PGPORT"],
                           error: run.error&.message)
  end
  raise "#{name} failed" if run.env["TEST_FAIL_HOOK"] == name
end

RailsDev.configure do |config|
  config.https = false
  config.http :web, port: Integer(ENV.fetch("TEST_RAILS_PORT"))
  config.http :js, port: Integer(ENV.fetch("TEST_VITE_PORT")), env: "VITE_PORT", url_env: "RAILS_DEV_VITE_URL", readiness: "/@vite/client"
  config.compose_file = "dev-docker-compose.yml"
  config.connect "postgres", port: 5432, env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" }
  config.before_start do |run|
    record.call("before_start", run)
    run.run(RbConfig.ruby, run.env.fetch("TEST_HOOK_COMMAND"), "before_start")
  end
  config.integrations << :prepare
  config.before_start do |run|
    next unless run.enabled?(:prepare)

    %w[deps:ruby deps:js db:prepare].each { |task| run.run("mise", "run", task) }
  end
  config.after_ready do |run|
    record.call("after_ready", run)
    run.run(RbConfig.ruby, run.env.fetch("TEST_HOOK_COMMAND"), "after_ready")
  end
  config.after_stop do |run|
    record.call("after_stop", run)
    run.run(RbConfig.ruby, run.env.fetch("TEST_HOOK_COMMAND"), "after_stop")
  end
  config.around_run do |run, continue|
    record.call("around_enter", run)
    continue.call
  ensure
    record.call("around_exit", run)
    run.run(RbConfig.ruby, run.env.fetch("TEST_HOOK_COMMAND"), "around_exit")
  end
end
