require_relative "../spec_helper"
require "miniloader/media_key"

RSpec.describe Miniloader::MediaKey do
  describe ".build" do
    it "builds a Jellyfin-style key for an episode" do
      plan = described_class.build("hermes", "raw_download.mp4", {
        "kind" => "episode", "show" => "Cosmos", "year" => "1980",
        "season" => "1", "episode" => "3", "episode_title" => "The Backbone of Night"
      })

      expect(plan.key).to eq(
        "Shows/Cosmos (1980)/Season 01/Cosmos (1980) - S01E03 - The Backbone of Night.mp4"
      )
      expect(plan.media_kind).to eq("episode")
      expect(plan.title).to eq("Cosmos")
      expect(plan.year).to eq(1980)
      expect(plan.season_number).to eq(1)
      expect(plan.episode_number).to eq(3)
      expect(plan.episode_title).to eq("The Backbone of Night")
    end

    it "builds an episode key without a year or episode title" do
      plan = described_class.build("hermes", "ep.mkv", {
        "kind" => "episode", "show" => "Cosmos", "season" => "1", "episode" => "3"
      })

      expect(plan.key).to eq("Shows/Cosmos/Season 01/Cosmos - S01E03.mkv")
    end

    it "builds a Jellyfin-style key for a movie" do
      plan = described_class.build("hermes", "download.mkv", {
        "kind" => "movie", "movie" => "Arrival", "year" => "2016"
      })

      expect(plan.key).to eq("Movies/Arrival (2016)/Arrival (2016).mkv")
      expect(plan.media_kind).to eq("movie")
      expect(plan.title).to eq("Arrival")
      expect(plan.year).to eq(2016)
    end

    it "builds a Podcasts-style key for a podcast episode" do
      plan = described_class.build("hermes", "raw.mp3", {
        "kind" => "podcast", "show" => "Accidental Tech Podcast",
        "episode" => "7", "episode_title" => "Coffee Ban"
      })

      expect(plan.key).to eq(
        "Podcasts/Accidental Tech Podcast/Accidental Tech Podcast - Ep007 - Coffee Ban.mp3"
      )
      expect(plan.media_kind).to eq("podcast")
      expect(plan.title).to eq("Accidental Tech Podcast")
      expect(plan.episode_number).to eq(7)
      expect(plan.episode_title).to eq("Coffee Ban")
      expect(plan.season_number).to be_nil
    end

    it "builds a podcast key without an episode title" do
      plan = described_class.build("hermes", "raw.mp3", {
        "kind" => "podcast", "show" => "ATP", "episode" => "12"
      })

      expect(plan.key).to eq("Podcasts/ATP/ATP - Ep012.mp3")
    end

    it "requires show and episode for kind=podcast" do
      expect do
        described_class.build("hermes", "raw.mp3", { "kind" => "podcast", "show" => "ATP" })
      end.to raise_error(Miniloader::MediaKey::InvalidMetadata, /episode is required/)
    end

    it "falls back to the flat, timestamped key when no kind is given" do
      plan = described_class.build("hermes", "voice memo.mp3", {})

      expect(plan.key).to match(%r{\Ahermes/\d{14}-[0-9a-f]{8}-voice_memo\.mp3\z})
      expect(plan.media_kind).to be_nil
    end

    it "sanitizes filesystem-unsafe characters in show/movie names" do
      plan = described_class.build("hermes", "ep.mp4", {
        "kind" => "episode", "show" => 'Weird: Show/Name?', "season" => "1", "episode" => "1"
      })

      expect(plan.key).not_to include("/Weird: Show/Name?/")
      expect(plan.key).to start_with("Shows/Weird_ Show_Name_/")
    end

    it "rejects an unknown kind" do
      expect do
        described_class.build("hermes", "f.mp4", { "kind" => "documentary" })
      end.to raise_error(Miniloader::MediaKey::InvalidMetadata, /unknown kind/)
    end

    it "requires show/season/episode for kind=episode" do
      expect do
        described_class.build("hermes", "f.mp4", { "kind" => "episode", "show" => "Cosmos" })
      end.to raise_error(Miniloader::MediaKey::InvalidMetadata, /season/)
    end

    it "requires movie for kind=movie" do
      expect do
        described_class.build("hermes", "f.mp4", { "kind" => "movie" })
      end.to raise_error(Miniloader::MediaKey::InvalidMetadata, /movie is required/)
    end

    it "rejects a non-integer season" do
      expect do
        described_class.build("hermes", "f.mp4", {
          "kind" => "episode", "show" => "Cosmos", "season" => "one", "episode" => "1"
        })
      end.to raise_error(Miniloader::MediaKey::InvalidMetadata, /season must be an integer/)
    end
  end
end
