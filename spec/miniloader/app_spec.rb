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

  def upload_file(bytes: "x" * 10, filename: "song.mp3", token: "hermes-token", fields: {})
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), "audio/mpeg", original_filename: filename)
    header "Authorization", "Bearer #{token}" if token
    post "/uploads", { file: file }.merge(fields)
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

  it "uploads an episode with a Jellyfin-style key and logs it for the catalog" do
    uploader = configure!
    upload_file(
      filename: "raw_download.mp4",
      fields: { kind: "episode", show: "Cosmos", year: "1980", season: "1", episode: "3",
                episode_title: "The Backbone of Night" }
    )
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["key"]).to eq(
      "Shows/Cosmos (1980)/Season 01/Cosmos (1980) - S01E03 - The Backbone of Night.mp4"
    )
    expect(uploader.uploads.first[:key]).to eq(body["key"])
  end

  it "uploads a movie with a Jellyfin-style key" do
    configure!
    upload_file(filename: "download.mp4", fields: { kind: "movie", movie: "Arrival", year: "2016" })
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["key"]).to eq("Movies/Arrival (2016)/Arrival (2016).mp4")
  end

  it "rejects episode uploads missing required metadata" do
    configure!
    upload_file(filename: "ep.mp4", fields: { kind: "episode", show: "Cosmos" })
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)["error"]).to match(/season/)
  end

  it "uploads a podcast episode with a Podcasts-style key" do
    configure!
    upload_file(
      filename: "raw.mp3",
      fields: { kind: "podcast", show: "Accidental Tech Podcast", episode: "7", episode_title: "Coffee Ban" }
    )
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["key"]).to eq("Podcasts/Accidental Tech Podcast/Accidental Tech Podcast - Ep007 - Coffee Ban.mp3")
  end

  it "rejects an unknown kind" do
    configure!
    upload_file(filename: "ep.mp4", fields: { kind: "documentary" })
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)["error"]).to match(/unknown kind/)
  end

  describe "GET /catalog" do
    it "requires a valid token" do
      configure!
      get "/catalog"
      expect(last_response.status).to eq(401)
    end

    it "lists uploaded episodes, optionally filtered by show and season" do
      configure!
      upload_file(filename: "ep1.mp4", fields: { kind: "episode", show: "Cosmos", season: "1", episode: "1" })
      upload_file(filename: "ep2.mp4", fields: { kind: "episode", show: "Cosmos", season: "2", episode: "1" })
      upload_file(filename: "song.mp3") # generic upload, no media metadata

      header "Authorization", "Bearer hermes-token"
      get "/catalog", kind: "episode", show: "Cosmos", season: "1"

      expect(last_response.status).to eq(200)
      rows = JSON.parse(last_response.body)["uploads"]
      expect(rows.size).to eq(1)
      expect(rows.first["season_number"]).to eq(1)
      expect(rows.first["title"]).to eq("Cosmos")
    end
  end
end
