require 'shorturl'

module Notaru
  module Plugin
    class Shorten
      include Cinch::Plugin

      def initialize(*args)
        super
      end	

      match Regexp.new(/(https?:\/\/[^ ]+)/i), method: :cmd_shorten, use_prefix: false
      def cmd_shorten(m, url)
        if url.length > 64
          begin
            shortened = ShortURL.shorten(url, :tinyurl)
            m.reply "Shortened: #{shortened}"
          rescue StandardError => e
            info e.to_s
          end
        end
      end
    end
  end
end
