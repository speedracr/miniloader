require_relative "../spec_helper"
require "miniloader/uploader"

RSpec.describe Miniloader::Uploader do
  describe ".content_type_for" do
    it "maps common media extensions so browsers play/preview instead of downloading" do
      expect(described_class.content_type_for("podcasts/x/ep.mp3")).to eq("audio/mpeg")
      expect(described_class.content_type_for("movies/x/x.mkv")).to eq("video/x-matroska")
      expect(described_class.content_type_for("shows/x/Season 01/ep.mp4")).to eq("video/mp4")
      expect(described_class.content_type_for("doc.pdf")).to eq("application/pdf")
    end

    it "is case-insensitive on the extension" do
      expect(described_class.content_type_for("ep.MP3")).to eq("audio/mpeg")
    end

    it "falls back to application/octet-stream for unknown extensions" do
      expect(described_class.content_type_for("hermes/1234-thing.bin")).to eq("application/octet-stream")
    end
  end
end
