# Configuration reference

See the [README](../README.md) for installation and everyday commands. Ruby examples below belong in `config/rails_dev.rb` unless another file is named.

## Configuration

Settings load in order:

1. Gem defaults.
2. `$XDG_CONFIG_HOME/rails-dev/config.rb`, defaulting to `~/.config/rails-dev/config.rb`.
3. Your app's `config/rails_dev.rb`.
4. Your app's optional `config/rails_dev.local.rb`.

Later assignments replace earlier values. Arrays and hooks can be extended or cleared. Repeated `http` declarations merge options, including readiness settings.

| Setting | Default |
| --- | --- |
| `name` | Derived from the checkout directory name |
| `procfile` | `"Procfile.dev"` |
| `web` | `"web"`, the primary HTTP process |
| `https` | `true` |
| `startup_timeout` | 90 seconds |
| `shutdown_timeout` | 5 seconds |
| `compose_file` | Unset; Docker management is off |

Use `--root PATH` to select the working directory, even when the Procfile lives in a subdirectory.

## Processes and environment

Foreman runs your original Procfile and handles sibling shutdown when a process exits. Its normal `.env` behavior applies. Values loaded by Foreman are unavailable to earlier preparation hooks; the app must supply those separately.

| Variable | Meaning |
| --- | --- |
| `PORT` | Selected port in the primary web process; other processes follow Foreman's usual numbering |
| `RAILS_PORT` | Primary web port, available to every process |
| `RAILS_DEV_URL` | Primary public URL |
| `RAILS_DEV_RUNTIME` | This instance's runtime directory |

Procfile commands have no terminal input. Use `services exec` for interactive commands. Rails-dev inherits your shell environment and removes the launcher's Bundler settings from child processes.

## Docker Compose

Extend the [PostgreSQL example](../README.md#add-docker-services) with the connections and service selections your app needs:

```ruby
RailsDev.configure do |config|
  config.connect "redis", port: 6379,
    env: { "REDIS_URL" => "redis://%{host}:%{port}/0" }
  config.connect "clickhouse", port: 8123,
    env: { "CLICKHOUSE_URL" => "http://%{host}:%{port}" }
  config.profiles = ["debug"]
  config.exclude_services = ["mail"]
  config.publish_ports["internal"] = [6379]
end
```

Templates accept `%{host}` and `%{port}`. Credentials and database names remain app settings. An inherited `DATABASE_URL` with a PGPORT-only mapping is rejected; map the URL or remove it from the launch environment.

- All Compose-enabled services start, respecting dependencies and profiles. Any service type can use explicit connection mappings.
- Declared publications and requested ports receive available loopback ports. Existing containers are reused.
- Healthchecks determine readiness where present; otherwise running status is enough.
- Required dependencies cannot be excluded. Host networking, scaled services, and conflicting or non-loopback publications are unsupported.

`rails-dev services start` starts shared services. `rails-dev services stop` stops them for **every instance**, keeping containers and volumes. Both require Compose configuration.

`services exec` preserves arguments, terminal input, and exit status. It skips web hooks and preserves `RAILS_ENV`. Without Compose configured, it uses the existing environment.

## Additional HTTP servers

Match the endpoint name to its Procfile process and declare the port variable that command consumes:

```ruby
RailsDev.configure do |config|
  config.http :js, port: 5173, env: "VITE_PORT",
                  url_env: "RAILS_DEV_VITE_URL", readiness: "/@vite/client"
end
```

Add to `Procfile.dev`:

```procfile
js: pnpm exec vite --host 127.0.0.1 --port ${VITE_PORT:-5173} --strictPort
```

Here, `js` is the process name. Vite's `--strictPort` makes a taken port fail; rails-dev retries confirmed bind conflicts without repeating preparation hooks.

Each endpoint gets a URL such as `https://my-app-3001-js.localhost`. `url_env` defaults to `RAILS_DEV_<PROCESS>_URL`, using uppercase and replacing hyphens with underscores. Processes that do not serve HTTP need no endpoint declaration.

## Hooks

```ruby
RailsDev.configure do |config|
  config.around_run do |run, continue|
    continue.call
  ensure
    run.say("Run finished")
  end
end
```

| Hook | When it runs |
| --- | --- |
| `before_start` | After services and connection mapping, before Foreman |
| `after_ready` | After enabled readiness checks pass |
| `around_run` | Around preparation, startup, and the app run; call its continuation once |
| `after_stop` | After processes stop and around hooks unwind, including on errors and interrupts |

Hooks run once per invocation. Before/ready hooks run in registration order; stop hooks run in reverse order and all are attempted. Cleanup errors do not replace an earlier failure. Clear inherited hooks with `config.before_start.clear`.

The context exposes `root`, `runtime`, `env`, `url(process = primary_web)`, `error`, and `enabled?(name)`. URLs become available after networking is allocated.

`run(*argv)` streams output; `capture(*argv)` returns stdout. Both use argument arrays without a shell and run in the app directory with `run.env`. Use `say(message)` for output and `check_for_interrupt` during long custom work.

## Optional processes

Declare a Procfile process with `config.optional` and select it through `--with`. For Stripe, install its CLI and run `stripe login` first:

```ruby
RailsDev.configure do |config|
  config.optional :stripe
  config.before_start do |run|
    next unless run.enabled?(:stripe)

    run.env["STRIPE_SIGNING_SECRET"] = run.capture("stripe", "listen", "--print-secret").strip
  end
end
```

Add to `Procfile.dev`, using your app's webhook path:

```procfile
stripe: stripe listen --skip-update --forward-to http://127.0.0.1:${RAILS_PORT}/pay/webhooks/stripe
```

Start with `rails-dev start --with stripe`. Foreman starts selected processes together, so webhooks can arrive before Rails is ready.

- `config.optional :listener, with: :payments` lets a selection enable a differently named process. Several processes can share one selection.
- For optional hook work alone, add a name to `config.integrations` and check `run.enabled?`. Unknown selections fail before startup.

## Readiness

The primary endpoint defaults to `GET /up`, expecting HTTP 200; other endpoints need an explicit check. Requests use loopback HTTP with the public hostname in the Host header.

```ruby
RailsDev.configure do |config|
  config.readiness = { request_timeout: 1, interval: 0.1 }
  config.http :web, readiness: { path: "/health", success: 200, timeout: 30 }
end
```

| Option | Meaning |
| --- | --- |
| `path`, `method`, `headers`, `body` | Request settings; method defaults to `GET` |
| `success` | Status code, array of codes, or callable receiving the response; defaults to `200` |
| `timeout` | Endpoint timeout, also bounded by `startup_timeout` |
| `request_timeout` | Timeout for each connection, read, or write; defaults to 1 second |
| `interval` | Polling interval; defaults to 0.1 seconds |

`config.readiness` supplies shared defaults; endpoint settings override them. Use `readiness: false` to disable a check or `readiness: ->(endpoint) { ... }` for a custom check. The endpoint exposes `name`, `port`, and `url`.

Custom checks must return promptly and manage their own timeouts. Checks gate `after_ready` and the Ready message, not process launch order or ongoing health. A timeout stops owned processes and removes their routes.

## Vite

For `rails_vite` and `rails-vite-plugin`, load both helpers in your Gemfile's development/test group:

```ruby
gem "rails-dev", "0.1.0", require: ["rails_dev/railtie", "rails_dev/rails_vite"]
```

Declare the [HTTP endpoint](#additional-http-servers) with `url_env: "RAILS_DEV_VITE_URL"`. Add the helper to your existing Vite configuration, keeping your other plugins. Its returned options can be customized:

```js
export default defineConfig(async ({ command }) => {
  const runtime = command === 'serve' ? process.env.RAILS_DEV_RUNTIME : undefined
  const development = runtime ? (await import(`${runtime}/vite.mjs`)).default() : undefined

  return {
    plugins: [development?.plugin, rails(development?.rails)],
  }
})
```

## Multiple runs from one checkout

Ports, URLs, Rails PID files, cookies, Vite metadata, and Vite caches are separate per run. Compiled JavaScript and CSS remain shared.

For independent restarts, make Puma's shared restart watcher conditional in `config/puma.rb`:

```ruby
plugin :tmp_restart unless ENV["RAILS_DEV_RUNTIME"]
```

## Local HTTPS

Use `rails-dev setup --port 8443` for another proxy port, or `config.https = false` for loopback HTTP. `.localhost` URLs work only on the developer's own machine.

## Tailscale

Follow the [Tailscale setup](../README.md#share-through-tailscale). On Linux, an administrator may need to grant operator access:

```sh
sudo tailscale set --operator="$USER"
```

Tailscale mode needs no local Portless setup. Each endpoint gets an HTTPS port on the machine's tailnet hostname. Existing Serve routes and tailnet permissions are preserved; Funnel is not enabled.

## Instances and recovery

| Status | Meaning |
| --- | --- |
| `starting` | Preparation or startup checks are running |
| `ready` | Startup and ready hooks completed |
| `orphaned` | The launcher exited, but verified processes remain |
| `stale` | No processes remain in the recorded groups |
| `interrupted` | Process ownership cannot be verified |

Status and saved URLs are not ongoing health checks. Use `rails-dev stop INSTANCE` for recovery; cleanup is not automatic after a forced launcher exit.

Unverified ownership keeps the record for inspection. Detached daemons and unrecorded processes cannot be recovered this way. Shared Docker services and the HTTPS proxy stay running.
