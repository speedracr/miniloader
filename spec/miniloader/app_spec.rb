require_relative "../spec_helper"
require_relative "../support/fake_uploader"
require "miniloader/config"
require "rack/test"
require "tempfile"

RSpec.describe Miniloader::App do
  include Rack::Test::Methods

  def app
    Miniloader::App
  end

  def base_env(overrides = {})
    {
      "B2_KEY_ID" => "k", "B2_APPLICATION_KEY" => "s", "B2_BUCKET" => "b",
      "B2_ENDPOINT" => "https://example.com", "B2_REGION" => "r",
      "B2_PUBLIC_URL_BASE" => "https://f000.backblazeb2.com/file/b",
      "MINILOADER_TOKENS" => "hermes:hermes-token",
      "MINILOADER_ALLOWED_EXTENSIONS" => ".mp3,.mp4",
      "MINILOADER_MAX_UPLOAD_BYTES" => "1000",
      "MINILOADER_RATE_LIMIT_PER_MINUTE" => "2",
      "MINILOADER_MAX_CONCURRENT_UPLOADS" => "5",
      "MINILOADER_MAX_CONCURRENT_UPLOADS_PER_CALLER" => "5",
      "MINILOADER_DAILY_BYTE_QUOTA" => "100000",
      "MINILOADER_MONTHLY_BYTE_QUOTA" => "1000000"
    }.merge(overrides)
  end

  def configure!(overrides = {})
    config = Miniloader::Config.new(base_env(overrides))
    db = Miniloader::DB.connect(":memory:")
    uploader = Miniloader::FakeUploader.new
    Miniloader::App.configure_dependencies!(config: config, db: db, uploader: uploader)
    uploader
  end

  def upload_file(bytes: "x" * 10, filename: "song.mp3", token: "hermes-token")
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), "audio/mpeg", original_filename: filename)
    header "Authorization", "Bearer #{token}" if token
    post "/uploads", { file: file }
  end

  it "reports healthy" do
    configure!
    get "/health"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["status"]).to eq("ok")
  end

  it "rejects requests without a valid token" do
    configure!
    upload_file(token: nil)
    expect(last_response.status).to eq(401)
  end

  it "rejects an unknown token" do
    configure!
    upload_file(token: "not-a-real-token")
    expect(last_response.status).to eq(401)
  end

  it "uploads a valid file and returns its permanent URL" do
    uploader = configure!
    upload_file
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["url"]).to start_with("https://f000.backblazeb2.com/file/test-bucket/hermes/")
    expect(body["size"]).to eq(10)
    expect(uploader.uploads.size).to eq(1)
  end

  it "rejects disallowed file extensions" do
    configure!
    upload_file(filename: "malware.exe")
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)["error"]).to match(/extension/)
  end

  it "rejects files over the size cap" do
    configure!
    upload_file(bytes: "x" * 2000)
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)["error"]).to match(/exceeds max upload size/)
  end

  it "enforces the per-minute rate limit" do
    configure!
    2.times { upload_file(filename: "a.mp3") }
    upload_file(filename: "b.mp3")
    expect(last_response.status).to eq(429)
    expect(JSON.parse(last_response.body)["error"]).to match(/rate limit/)
  end

  it "enforces the daily byte quota" do
    configure!("MINILOADER_DAILY_BYTE_QUOTA" => "15")
    upload_file(bytes: "x" * 10, filename: "a.mp3")
    upload_file(bytes: "x" * 10, filename: "b.mp3")
    expect(last_response.status).to eq(429)
    expect(JSON.parse(last_response.body)["error"]).to match(/daily byte quota/)
  end

  it "disables local path uploads unless MINILOADER_LOCAL_PATH_ROOT is set" do
    configure!
    header "Authorization", "Bearer hermes-token"
    header "Content-Type", "application/json"
    post "/uploads", JSON.generate(path: "/etc/passwd")
    expect(last_response.status).to eq(403)
  end
end
