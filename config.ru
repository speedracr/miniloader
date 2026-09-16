require "dotenv/load"
require_relative "lib/miniloader/app"
require_relative "lib/miniloader/config"

Miniloader::App.configure_dependencies!(config: Miniloader::Config.load)

run Miniloader::App
