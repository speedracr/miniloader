require "sequel"
require "fileutils"

module Miniloader
  module DB
    SCHEMA_PATH = File.expand_path("../../db/schema.sql", __dir__)

    def self.connect(path)
      FileUtils.mkdir_p(File.dirname(path)) unless path == ":memory:"
      db = Sequel.sqlite(path == ":memory:" ? nil : path)
      File.read(SCHEMA_PATH).split(";").map(&:strip).reject(&:empty?).each do |statement|
        db.run(statement)
      end
      db
    end
  end
end
