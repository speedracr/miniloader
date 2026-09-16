module Miniloader
  class Quota
    def initialize(db, daily_byte_quota:, monthly_byte_quota:)
      @db = db
      @daily_byte_quota = daily_byte_quota
      @monthly_byte_quota = monthly_byte_quota
    end

    # Returns nil if the upload fits within quota, otherwise an error string.
    def check(caller, upload_bytes)
      day_used = bytes_since(caller, Time.now.utc - 86_400)
      if day_used + upload_bytes > @daily_byte_quota
        return "daily byte quota exceeded (#{@daily_byte_quota} bytes/24h)"
      end

      month_used = bytes_since(caller, Time.now.utc - 30 * 86_400)
      if month_used + upload_bytes > @monthly_byte_quota
        return "monthly byte quota exceeded (#{@monthly_byte_quota} bytes/30d)"
      end

      nil
    end

    private

    def bytes_since(caller, since)
      @db[:uploads]
        .where(caller: caller)
        .where(Sequel.lit("created_at >= ?", since.iso8601))
        .sum(:bytes) || 0
    end
  end
end
