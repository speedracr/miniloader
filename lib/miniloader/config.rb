module Miniloader
  class Config
    class MissingEnv < StandardError; end

    attr_reader :b2_key_id, :b2_application_key, :b2_bucket, :b2_endpoint, :b2_region,
                :b2_public_url_base, :tokens, :bind, :port, :db_path,
                :max_upload_bytes, :allowed_extensions, :rate_limit_per_minute,
                :max_concurrent_uploads, :max_concurrent_uploads_per_caller,
                :daily_byte_quota, :monthly_byte_quota, :local_path_root

    def initialize(env = ENV)
      @b2_key_id = fetch(env, "B2_KEY_ID")
      @b2_application_key = fetch(env, "B2_APPLICATION_KEY")
      @b2_bucket = fetch(env, "B2_BUCKET")
      @b2_endpoint = fetch(env, "B2_ENDPOINT")
      @b2_region = fetch(env, "B2_REGION")
      @b2_public_url_base = fetch(env, "B2_PUBLIC_URL_BASE").chomp("/")

      @tokens = parse_tokens(fetch(env, "MINILOADER_TOKENS"))

      @bind = env.fetch("MINILOADER_BIND", "127.0.0.1")
      @port = Integer(env.fetch("MINILOADER_PORT", "4567"))
      @db_path = env.fetch("MINILOADER_DB_PATH", "db/miniloader.sqlite3")

      @max_upload_bytes = Integer(env.fetch("MINILOADER_MAX_UPLOAD_BYTES", "2147483648"))
      @allowed_extensions = env.fetch("MINILOADER_ALLOWED_EXTENSIONS", "")
                                .split(",").map { |e| e.strip.downcase }.reject(&:empty?)
      @rate_limit_per_minute = Integer(env.fetch("MINILOADER_RATE_LIMIT_PER_MINUTE", "5"))
      @max_concurrent_uploads = Integer(env.fetch("MINILOADER_MAX_CONCURRENT_UPLOADS", "2"))
      @max_concurrent_uploads_per_caller =
        Integer(env.fetch("MINILOADER_MAX_CONCURRENT_UPLOADS_PER_CALLER", "1"))
      @daily_byte_quota = Integer(env.fetch("MINILOADER_DAILY_BYTE_QUOTA", "10737418240"))
      @monthly_byte_quota = Integer(env.fetch("MINILOADER_MONTHLY_BYTE_QUOTA", "107374182400"))

      # Optional: when set, POST /uploads accepts {"path": "..."} for files that
      # already live on this machine, restricted to this directory. Disabled by
      # default since it lets a caller make the service read arbitrary local files.
      local_root = env["MINILOADER_LOCAL_PATH_ROOT"]
      @local_path_root = local_root && File.realpath(local_root)
    end

    def self.load(env = ENV)
      new(env)
    end

    private

    def fetch(env, key)
      value = env[key]
      raise MissingEnv, "missing required env var #{key}" if value.nil? || value.strip.empty?

      value
    end

    def parse_tokens(raw)
      pairs = raw.split(",").map(&:strip).reject(&:empty?).map do |pair|
        name, token = pair.split(":", 2)
        raise MissingEnv, "malformed MINILOADER_TOKENS entry: #{pair.inspect}" if name.nil? || token.nil?

        [token, name]
      end
      pairs.to_h.freeze
    end
  end
end
