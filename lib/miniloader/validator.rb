module Miniloader
  class Validator
    def initialize(max_upload_bytes:, allowed_extensions:)
      @max_upload_bytes = max_upload_bytes
      @allowed_extensions = allowed_extensions
    end

    # Returns nil if the upload is acceptable, otherwise an error string.
    def validate(filename:, size:)
      ext = File.extname(filename).downcase
      unless @allowed_extensions.include?(ext)
        return "file extension #{ext.empty? ? "(none)" : ext} is not allowed"
      end

      return "file exceeds max upload size of #{@max_upload_bytes} bytes" if size > @max_upload_bytes

      nil
    end
  end
end
