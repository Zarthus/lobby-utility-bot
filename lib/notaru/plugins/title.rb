require 'addressable/uri'
require 'nokogiri'
require 'unirest'

module Notaru
  module Plugin
    class Title
      PREFIX_REGEXP = '(?:^|\s+)!'.freeze

      include Cinch::Plugin

      def initialize(*args)
        super

        # Supported keys: title, url, host, nick
        @format = @bot.config.title_format
        # List of Regexes
        @ignore = []
        @bot.config.title_ignore.each do |regex|
          @ignore << Regexp.new(regex)
        end

        # Do not send any message if title could not be retrieved.
        @silent_on_failure = @bot.config.title_silent_on_fail

        # The prefix char (without ^)
        self.class.const_set(
          :PREFIX_REGEXP_OVERRIDE,
          '(?:^|\s+)' + (@bot.config.prefix_char.nil? ? '!' : @bot.config.prefix_char)
        )

        Unirest.user_agent("NotaruIRCBot/#{VERSION}")
      end

      match Regexp.new('t(?:itle)? ([^ ]+)'),
            method: :cmd_title,
            prefix: Regexp.new(
              defined?(PREFIX_REGEXP_OVERRIDE) ? PREFIX_REGEXP_OVERRIDE : PREFIX_REGEXP
            )

      def cmd_title(m, url)
        url = "http://#{url}" unless url.start_with?('http')

        uri = Addressable::URI.parse(url).normalize
        title = find_title(uri)

        if title && !title.empty?
          m.reply(@format % {
            title: title.gsub(/\s+/, ' ').strip,
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
          return true if url.host =~ regex
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
