require 'addressable/uri'
require 'nokogiri'
require 'unirest'

module Notaru
  module Plugin
    class Title
      include Cinch::Plugin

      def initialize(*args)
        # Supported keys: title, url, host, nick
        @format = 'Title: \'%{title}\' at %{host}'
        # List of Regexes
        @ignore = []
        # Do not send any message if title could not be retrieved.
        @silent_on_failure = false

        Unirest.user_agent("NotaruIRCBot/#{VERSION}")
        super
      end

      match Regexp.new('t(?:itle)? ([^ ]+)$'), method: :cmd_title
      def cmd_title(m, url)
        uri = Addressable::URI.parse(url).normalize
        title = find_title(uri)

        if title && !title.empty?
          m.reply(@format % {
              title: title,
              url: url,
              host: uri.host,
              nick: m.user.nick
          })
        elsif title && title.empty?
          unless @silent_on_failure
            m.user.notice("Could not retrieve a valid title from #{uri.host}")
          end
        else
          unless @silent_on_failure
            m.user.notice('Sorry, I was unable to retrieve the title.')
          end
        end
      end

      # @param uri [Addressable::URI]
      # @return [String, false]
      def find_title(uri)
        if !uri || !valid_url?(uri) || ignored?(uri)
          debug("Won't fetch HTML for #{uri.inspect}, uri is falsy, invalid, or ignored.")
          return false
        end

        html = fetch_html(uri)

        if !html || html.empty?
          debug("Unable to fetch HTML for #{uri.host} (HTML: #{html.inspect})")
          return false
        end

        Nokogiri::HTML(html).css('title').text
      end

      # @param url [Addressable::URI]
      # @return [Boolean]
      def ignored?(url)
        @ignore.each do |regex|
          if url.host =~ regex
            return true
          end
        end

        false
      end

      # @param url [Addressable::URI]
      # @return [Boolean]
      def valid_url?(url)
        url.scheme =~ /https?/
      end

      # @param [Addressable::URI, String] uri
      # @return [String, false]
      def fetch_html(uri)
        response = Unirest.get(uri.to_s)

        return false if response.code != 200

        response.body
      end
    end
  end
end
