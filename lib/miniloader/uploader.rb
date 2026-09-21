require "aws-sdk-s3"

module Miniloader
  class Uploader
    # Without an explicit Content-Type, B2 stores objects as
    # application/octet-stream, which makes browsers download rather than
    # play/preview them. Covers the media types this service is meant for;
    # anything else falls back to application/octet-stream (still downloads,
    # but that's the right behavior for e.g. arbitrary documents).
    CONTENT_TYPES = {
      ".mp3" => "audio/mpeg",
      ".m4a" => "audio/mp4",
      ".wav" => "audio/wav",
      ".flac" => "audio/flac",
      ".ogg" => "audio/ogg",
      ".mp4" => "video/mp4",
      ".m4v" => "video/mp4",
      ".mkv" => "video/x-matroska",
      ".mov" => "video/quicktime",
      ".webm" => "video/webm",
      ".pdf" => "application/pdf",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".gif" => "image/gif",
      ".txt" => "text/plain"
    }.freeze
    DEFAULT_CONTENT_TYPE = "application/octet-stream"

    def initialize(config)
      @bucket = config.b2_bucket
      @public_url_base = config.b2_public_url_base
      @client = Aws::S3::Client.new(
        access_key_id: config.b2_key_id,
        secret_access_key: config.b2_application_key,
        endpoint: config.b2_endpoint,
        region: config.b2_region,
        force_path_style: true
      )
    end

    # Uploads the local file at `path` under `key` and returns its public URL.
    def upload(path, key)
      File.open(path, "rb") do |file|
        @client.put_object(bucket: @bucket, key: key, body: file, content_type: self.class.content_type_for(key))
      end
      "#{@public_url_base}/#{key}"
    end

    def self.content_type_for(key)
      CONTENT_TYPES.fetch(File.extname(key).downcase, DEFAULT_CONTENT_TYPE)
    end
  end
end
