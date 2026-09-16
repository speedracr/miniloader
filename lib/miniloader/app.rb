require "sinatra/base"
require "json"
require "digest"
require "securerandom"

require_relative "config"
require_relative "db"
require_relative "auth"
require_relative "rate_limiter"
require_relative "quota"
require_relative "validator"
require_relative "uploader"

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

      path, filename = resolve_upload_source
      halt_json 400, "no file or path provided" unless path

      size = File.size(path)

      error = self.class.validator.validate(filename: filename, size: size)
      halt_json 422, error if error

      error = self.class.quota.check(caller_name, size)
      halt_json 429, error if error

      acquisition = self.class.rate_limiter.try_acquire(caller_name)
      halt_json 429, acquisition.reason unless acquisition.allowed?

      begin
        sha256 = Digest::SHA256.file(path).hexdigest
        key = build_key(caller_name, filename)
        url = self.class.uploader.upload(path, key)

        self.class.db[:uploads].insert(
          caller: caller_name,
          filename: filename,
          bytes: size,
          sha256: sha256,
          b2_key: key,
          url: url,
          created_at: Time.now.utc.iso8601
        )

        json_body(url: url, key: key, size: size, sha256: sha256)
      rescue StandardError => e
        halt_json 502, "upload failed: #{e.message}"
      ensure
        self.class.rate_limiter.release(caller_name)
      end
    end

    private

    def bearer_token
      header = request.env["HTTP_AUTHORIZATION"]
      return nil unless header

      match = header.match(/\ABearer\s+(.+)\z/)
      match && match[1]
    end

    # Returns [local_path, display_filename] for either a multipart "file" field
    # or a {"path": "..."} JSON body (only when MINILOADER_LOCAL_PATH_ROOT is set).
    def resolve_upload_source
      file_param = params[:file]
      return [file_param[:tempfile].path, file_param[:filename]] if file_param&.fetch(:tempfile, nil)

      body = parse_json_body
      path = body && body["path"]
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

    def build_key(caller_name, filename)
      ext = File.extname(filename)
      base = File.basename(filename, ext).gsub(/[^a-zA-Z0-9_-]/, "_")
      timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
      "#{caller_name}/#{timestamp}-#{SecureRandom.hex(4)}-#{base}#{ext}"
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
