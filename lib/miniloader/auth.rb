module Miniloader
  class Auth
    def initialize(tokens)
      @tokens = tokens
    end

    # Returns the caller name for a valid token, or nil.
    def caller_for(token)
      return nil if token.nil? || token.empty?

      @tokens[token]
    end
  end
end
