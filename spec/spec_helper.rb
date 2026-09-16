require "rack/test"
require "rspec"

ENV["B2_KEY_ID"] ||= "test-key-id"
ENV["B2_APPLICATION_KEY"] ||= "test-secret"
ENV["B2_BUCKET"] ||= "test-bucket"
ENV["B2_ENDPOINT"] ||= "https://s3.example-region.backblazeb2.com"
ENV["B2_REGION"] ||= "example-region"
ENV["B2_PUBLIC_URL_BASE"] ||= "https://f000.backblazeb2.com/file/test-bucket"
ENV["MINILOADER_TOKENS"] ||= "hermes:hermes-token,podcast:podcast-token"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "miniloader/app"
require "miniloader/db"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
