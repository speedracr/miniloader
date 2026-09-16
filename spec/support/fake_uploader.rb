module Miniloader
  class FakeUploader
    attr_reader :uploads

    def initialize(public_url_base: "https://f000.backblazeb2.com/file/test-bucket")
      @public_url_base = public_url_base
      @uploads = []
    end

    def upload(path, key)
      @uploads << { path: path, key: key }
      "#{@public_url_base}/#{key}"
    end
  end
end
