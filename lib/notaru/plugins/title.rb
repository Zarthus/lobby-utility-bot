require 'net/https'
require 'addressable/uri'
require 'nokogiri'

module Notaru
  module Plugin
    class Title
      include Cinch::Plugin

      def initialize(*args)
        # Supported keys: title, url, host, nick
        @format = 'Title: \'%{title}\' at %{host} (%{nick})'
        # List of Regexes
        @ignore = []
        # Do not send any message if title could not be retrieved.
        @silent_on_failure = false

        super
      end

      match Regexp.new('t(?:itle)? ([^ ]+)$'), method: :cmd_title
      def cmd_title(m, url)
        uri = Addressable::URI.parse(url)
        title = find_title(uri)

        if title
          m.channel.msg(@format % {
              title: title,
              url: url,
              host: uri.host,
              nick: m.user.nick
          })
        else
          unless @silent_on_failure
            m.reply('Sorry, I was unable to retrieve the title.')
          end
        end
      end

      # @param uri [Addressable::URI]
      # @return [String, false]
      def find_title(uri)
        if !uri || !valid_url?(uri) || ignored?(uri)
          return false
        end

        request = Net::HTTP.get(uri.host, uri.path, uri.port)

        begin
          request.value
        rescue
          info("HTTP Request for #{uri.host} failed.")
          return false
        end

        Nokogiri::HTML(request.body).css('title').text
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
    end
  end
end
