require "dotenv/load"

bind_host = ENV.fetch("MINILOADER_BIND", "127.0.0.1")
port = ENV.fetch("MINILOADER_PORT", "4567")

bind "tcp://#{bind_host}:#{port}"
workers 0
threads 2, 4
