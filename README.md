# rails-dev

Run Rails on an available port, get a local HTTPS URL, and share it through Tailscale when needed. Start several instances from the same checkout; each gets its own URL.

Works on macOS and Linux with ERB or Vite apps. Foreman runs your Procfile. Your app chooses its tools and preparation commands; rails-dev handles ports, HTTPS, and optional Docker Compose services.

## Install

| Requirement | When you need it |
| --- | --- |
| Ruby 3.4+ | Always; Foreman is included as a dependency |
| Node.js 24+ and npm | Local HTTPS |
| Docker Compose 2.24.4+ | Managed Docker services |
| Connected Tailscale client | Sharing over your tailnet |

The gem is not published yet. From the rails-dev checkout, using the same Ruby as your app:

```sh
bundle install
bundle exec rake build
gem install --local pkg/rails-dev-0.1.0.gem
```

## Set up your app

Use your app's usual shell environment and install its dependencies first. Mise is optional.

**1. Add the Rails helper to your Gemfile**, then run `bundle install`:

```ruby
group :development, :test do
  gem "rails-dev", "0.1.0", require: "rails_dev/railtie"
end
```

The helper configures hostnames, route and mailer URLs, and cookies for each instance. Apps using `rails_vite` also need the [Vite setup](docs/reference.md#vite).

**2. Put your server command in `Procfile.dev`:**

```procfile
web: bin/rails server -b 127.0.0.1
```

Keep your existing workers and asset watchers there too. Let commands use the supplied ports; fixed ports in commands or `.env` can override them.

Configure [Docker services](#add-docker-services) or [preparation hooks](docs/reference.md#hooks) before starting if your app needs them.

**3. Set up local HTTPS once per machine, then start from your app directory:**

```sh
rails-dev setup
rails-dev start
```

`setup` installs the Portless proxy and certificate trust. `start` picks a free port starting at 3000 and prints a URL such as `https://my-app-3001.localhost`.

Startup waits for `GET /up` to return HTTP 200. [Change the readiness check](docs/reference.md#readiness) if your app uses another health endpoint.

Run `start` in another terminal for a second instance. **Ctrl+C stops that instance**; shared Docker services stay running.

## Everyday commands

| Task | Command |
| --- | --- |
| Start an instance | `rails-dev start` |
| List your instances across projects | `rails-dev list` |
| List one checkout's instances | `rails-dev list --root .` |
| Stop an instance using its listed ID | `rails-dev stop INSTANCE` |
| Check local HTTPS | `rails-dev doctor` |
| See command options | `rails-dev --help` |

If a terminal or launcher exits unexpectedly, use `list` and `stop` to recover the instance. [Status and recovery details](docs/reference.md#instances-and-recovery).

## Add Docker services

Create `config/rails_dev.rb` in your app. For PostgreSQL:

```ruby
RailsDev.configure do |config|
  config.compose_file = "dev-docker-compose.yml"
  config.connect "postgres", port: 5432,
    env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" }

  config.before_start { |run| run.run("bin/rails", "db:prepare") }
end
```

Use your Compose filename and service name. Rails-dev starts enabled services and publishes their declared ports on available loopback ports. It supplies the connection variables you map; your app provides database names and credentials.

If your app uses `DATABASE_URL`, map it instead of leaving a fixed URL that overrides `PGHOST` and `PGPORT`. See [Compose configuration](docs/reference.md#docker-compose) for Redis, ClickHouse, profiles, and exclusions.

```sh
rails-dev services exec -- bin/rails console
RAILS_ENV=test rails-dev services exec -- bin/rails test
```

These commands start or reuse services and pass their connections to the host command. Rails does not need to be running.

## Share through Tailscale

Connect Tailscale and enable HTTPS in your tailnet's DNS settings, then run:

```sh
rails-dev start --tailscale
```

Open the printed URL from another device allowed to reach your machine on the tailnet. Each instance uses its own HTTPS port. [Tailscale permissions and setup](docs/reference.md#tailscale).

## Customize

App settings live in `config/rails_dev.rb` and override global defaults. Keep personal overrides in `config/rails_dev.local.rb` and add that file to your app's ignore list.

| What you want to change | Guide |
| --- | --- |
| App name, ports, Procfile, or defaults | [Configuration](docs/reference.md#configuration) |
| Environment and process commands | [Processes and environment](docs/reference.md#processes-and-environment) |
| More HTTP servers | [Additional HTTP servers](docs/reference.md#additional-http-servers) |
| Preparation and lifecycle hooks | [Hooks](docs/reference.md#hooks) |
| Optional processes, such as Stripe | [Optional processes](docs/reference.md#optional-processes) |
| Vite URLs and hot reload | [Vite](docs/reference.md#vite) |
| Independent restarts and shared assets | [Multiple runs](docs/reference.md#multiple-runs-from-one-checkout) |
| Plain HTTP or a different HTTPS proxy port | [Local HTTPS](docs/reference.md#local-https) |

OAuth relay, public webhook relay, and direct LAN HTTPS are deferred.

## Development

```sh
mise ci
mise run test:docker
mise run test:https
```

Without Mise, use `bundle exec rake test rubocop build`, `bundle exec rake test_docker`, and `bundle exec rake test_https`.

Tests use Minitest. CI covers Ruby 3.4 and 4.0 on Linux and macOS.
