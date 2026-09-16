require "securerandom"

module Miniloader
  # Builds B2 object keys. TV episodes and movies get a Jellyfin/Kodi-style
  # path (Shows/<Show> (<Year>)/Season NN/<Show> (<Year>) - SxxEyy - <Title>.ext,
  # Movies/<Movie> (<Year>)/<Movie> (<Year>).ext) so the bucket is browsable and
  # scannable without a separate metadata database. Uploads without that
  # metadata (kind omitted) fall back to the original flat, timestamped key.
  class MediaKey
    class InvalidMetadata < StandardError; end

    Plan = Struct.new(
      :key, :media_kind, :title, :year, :season_number, :episode_number, :episode_title,
      keyword_init: true
    )

    def self.build(caller_name, filename, data)
      ext = File.extname(filename)
      kind = string_field(data, :kind)&.downcase

      case kind
      when "episode" then build_episode(filename, ext, data)
      when "movie" then build_movie(filename, ext, data)
      when nil then build_generic(caller_name, filename, ext)
      else
        raise InvalidMetadata, "unknown kind #{kind.inspect} (expected \"episode\", \"movie\", or omitted)"
      end
    end

    def self.build_episode(_filename, ext, data)
      show = require_field(data, :show, "show")
      season = require_integer(data, :season, "season")
      episode = require_integer(data, :episode, "episode")
      year = optional_integer(data, :year, "year")
      episode_title = string_field(data, :episode_title)

      show_label = year ? "#{show} (#{year})" : show
      code = format("S%02dE%02d", season, episode)
      file_base = [show_label, code, episode_title].compact.join(" - ")

      key = [
        "Shows",
        sanitize(show_label),
        format("Season %02d", season),
        "#{sanitize(file_base)}#{ext}"
      ].join("/")

      Plan.new(key: key, media_kind: "episode", title: show, year: year,
               season_number: season, episode_number: episode, episode_title: episode_title)
    end

    def self.build_movie(_filename, ext, data)
      movie = require_field(data, :movie, "movie")
      year = optional_integer(data, :year, "year")
      movie_label = year ? "#{movie} (#{year})" : movie

      key = [
        "Movies",
        sanitize(movie_label),
        "#{sanitize(movie_label)}#{ext}"
      ].join("/")

      Plan.new(key: key, media_kind: "movie", title: movie, year: year,
               season_number: nil, episode_number: nil, episode_title: nil)
    end

    def self.build_generic(caller_name, filename, ext)
      base = File.basename(filename, ext).gsub(/[^a-zA-Z0-9_-]/, "_")
      timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
      key = "#{caller_name}/#{timestamp}-#{SecureRandom.hex(4)}-#{base}#{ext}"

      Plan.new(key: key, media_kind: nil, title: nil, year: nil,
               season_number: nil, episode_number: nil, episode_title: nil)
    end
    private_class_method :build_episode, :build_movie, :build_generic

    def self.string_field(data, key)
      value = data[key.to_s]
      value = data[key.to_sym] if value.nil?
      return nil if value.nil?

      value = value.to_s.strip
      value.empty? ? nil : value
    end

    def self.require_field(data, key, label)
      string_field(data, key) || raise(InvalidMetadata, "#{label} is required for this upload kind")
    end

    def self.optional_integer(data, key, label)
      raw = string_field(data, key)
      return nil if raw.nil?

      Integer(raw)
    rescue ArgumentError, TypeError
      raise InvalidMetadata, "#{label} must be an integer"
    end

    def self.require_integer(data, key, label)
      optional_integer(data, key, label) || raise(InvalidMetadata, "#{label} is required and must be an integer")
    end

    def self.sanitize(segment)
      cleaned = segment.to_s.strip.gsub(%r{[/\\:*?"<>|]}, "_").squeeze(" ")
      raise InvalidMetadata, "resulting path segment is empty" if cleaned.empty?

      cleaned
    end
    private_class_method :string_field, :require_field, :optional_integer, :require_integer, :sanitize
  end
end
