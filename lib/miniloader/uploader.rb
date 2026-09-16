require "aws-sdk-s3"

module Miniloader
  class Uploader
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
        @client.put_object(bucket: @bucket, key: key, body: file)
      end
      "#{@public_url_base}/#{key}"
    end
  end
end
