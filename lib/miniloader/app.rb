require "sinatra/base"
require "json"
require "digest"

require_relative "config"
require_relative "db"
require_relative "auth"
require_relative "rate_limiter"
require_relative "quota"
require_relative "validator"
require_relative "uploader"
require_relative "media_key"

module Miniloader
  class App < Sinatra::Base
    set :show_exceptions, false
    set :raise_errors, false
    # Token-authenticated JSON API called by local scripts/services, not a browser:
    # rack-protection's CSRF checks don't apply, and the Host header isn't a
    # meaningful trust boundary here (the bearer token and network bind are).
    set :protection, false
    set :host_authorization, permitted_hosts: []

    class << self
      attr_accessor :config, :db, :auth, :rate_limiter, :quota, :validator, :uploader
    end

    # Wires up all dependencies. Callers may override any of them (used by specs
    # to inject a fake uploader / in-memory db instead of hitting real B2).
    def self.configure_dependencies!(config:, db: nil, uploader: nil)
      self.config = config
      self.db = db || DB.connect(config.db_path)
      self.auth = Auth.new(config.tokens)
      self.rate_limiter = RateLimiter.new(
        rate_limit_per_minute: config.rate_limit_per_minute,
        max_concurrent: config.max_concurrent_uploads,
        max_concurrent_per_caller: config.max_concurrent_uploads_per_caller
      )
      self.quota = Quota.new(
        self.db,
        daily_byte_quota: config.daily_byte_quota,
        monthly_byte_quota: config.monthly_byte_quota
      )
      self.validator = Validator.new(
        max_upload_bytes: config.max_upload_bytes,
        allowed_extensions: config.allowed_extensions
      )
      self.uploader = uploader || Uploader.new(config)
      self
    end

    get "/health" do
      json_body(status: "ok")
    end

    post "/uploads" do
      caller_name = self.class.auth.caller_for(bearer_token)
      halt_json 401, "unauthorized" unless caller_name

      data = input_data
      path, filename = resolve_upload_source(data)
      halt_json 400, "no file or path provided" unless path

      size = File.size(path)

      error = self.class.validator.validate(filename: filename, size: size)
      halt_json 422, error if error

      error = self.class.quota.check(caller_name, size)
      halt_json 429, error if error

      plan = begin
        MediaKey.build(caller_name, filename, data)
      rescue MediaKey::InvalidMetadata => e
        halt_json 422, e.message
      end

      acquisition = self.class.rate_limiter.try_acquire(caller_name)
      halt_json 429, acquisition.reason unless acquisition.allowed?

      begin
        sha256 = Digest::SHA256.file(path).hexdigest
        url = self.class.uploader.upload(path, plan.key)

        self.class.db[:uploads].insert(
          caller: caller_name,
          filename: filename,
          bytes: size,
          sha256: sha256,
          b2_key: plan.key,
          url: url,
          created_at: Time.now.utc.iso8601,
          media_kind: plan.media_kind,
          title: plan.title,
          year: plan.year,
          season_number: plan.season_number,
          episode_number: plan.episode_number,
          episode_title: plan.episode_title
        )

        json_body(url: url, key: plan.key, size: size, sha256: sha256)
      rescue StandardError => e
        halt_json 502, "upload failed: #{e.message}"
      ensure
        self.class.rate_limiter.release(caller_name)
      end
    end

    # Read-only view over the upload log, e.g. GET /catalog?kind=episode&show=Foo
    # Lets other services (or a future Jellyfin-adjacent tool) discover what's in
    # the bucket without listing/parsing B2 keys themselves.
    get "/catalog" do
      caller_name = self.class.auth.caller_for(bearer_token)
      halt_json 401, "unauthorized" unless caller_name

      dataset = self.class.db[:uploads]
      dataset = dataset.where(media_kind: params[:kind]) if present?(params[:kind])
      dataset = dataset.where(title: params[:show]) if present?(params[:show])
      dataset = dataset.where(title: params[:movie]) if present?(params[:movie])
      if present?(params[:season])
        dataset = dataset.where(season_number: Integer(params[:season]))
      end

      rows = dataset.order(:title, :season_number, :episode_number, :created_at).all
      json_body(uploads: rows)
    rescue ArgumentError
      halt_json 400, "season must be an integer"
    end

    private

    def present?(value)
      !value.nil? && !value.to_s.strip.empty?
    end

    def bearer_token
      header = request.env["HTTP_AUTHORIZATION"]
      return nil unless header

      match = header.match(/\ABearer\s+(.+)\z/)
      match && match[1]
    end

    # Metadata (path, and media kind/show/season/episode/... fields) comes from
    # multipart form fields alongside the file, or from a JSON body for
    # path-based uploads. Either way this gives resolve_upload_source and
    # MediaKey.build one consistent hash to read from.
    def input_data
      json_request? ? (parse_json_body || {}) : params
    end

    def json_request?
      (request.media_type || "").start_with?("application/json")
    end

    # Returns [local_path, display_filename] for either a multipart "file" field
    # or a {"path": "..."} JSON body (only when MINILOADER_LOCAL_PATH_ROOT is set).
    def resolve_upload_source(data)
      file_param = data[:file] || data["file"]
      return [file_param[:tempfile].path, file_param[:filename]] if file_param.respond_to?(:[]) && file_param[:tempfile]

      path = data["path"] || data[:path]
      return [nil, nil] unless path

      root = self.class.config.local_path_root
      halt_json 403, "local path uploads are disabled" unless root

      resolved = begin
        File.realpath(path)
      rescue Errno::ENOENT
        nil
      end
      halt_json 400, "path not found" unless resolved
      halt_json 403, "path outside allowed directory" unless resolved.start_with?("#{root}#{File::SEPARATOR}")

      [resolved, File.basename(resolved)]
    end

    def parse_json_body
      request.body.rewind
      raw = request.body.read
      return nil if raw.nil? || raw.strip.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      halt_json 400, "invalid JSON body"
    end

    def json_body(payload)
      content_type :json
      JSON.generate(payload)
    end

    def halt_json(status, message)
      halt status, json_body(error: message)
    end
  end
end
