require 'addressable/uri'
require 'nokogiri'
require 'rest-client'

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

        @useragent = "NotaruIRCBot/#{VERSION}"

        @last_recorded_url = nil
        @last_title_url = nil
        @warnings = {}
        @warning_ban_duration = 10
        @warning_reset_timer = 60 * 60 * 6

        Timer(@warning_reset_timer) do
            @warnings = {}
        end
      end

      match Regexp.new('t(?:its?(?:le)?)?(?: ([^ ]+))?'),
            method: :cmd_title,
            prefix: Regexp.new(
              defined?(PREFIX_REGEXP_OVERRIDE) ? PREFIX_REGEXP_OVERRIDE : PREFIX_REGEXP
            )
      match Regexp.new('(https?:\/\/[^\s]+)'), method: :record_url, use_prefix: false

      def cmd_title(m, url, try_again = true)
        unless url
          unless @last_recorded_url
            return m.user.notice("No last-known URL (last_recorded_url = #{@last_recorded_url.inspect}), " +
              "please supply the optional argument 'url'.")
          end

          url = @last_recorded_url
       end

        url = "http://#{url}" unless url.start_with?('http')

        if !@last_title_url.nil? && @last_title_url == url
          warn_user(m)
          @last_recorded_url = nil
          return
        end

        uri = Addressable::URI.parse(url).normalize
        title = find_title(uri)

        if title && !title.empty?
          m.reply(@format % {
            title: title.tr('#', '\\').gsub(/\s+/, ' ').strip.tr("\n", ''),
            url: url,
            host: uri.host,
            nick: m.user.nick
          })
          @last_title_url = url
          @last_recorded_url = nil
        elsif title && title.empty?
          if try_again && (/imgur.com\/[^.]+(\.\w+)$/i.match(url) || /(\.(?:jpg|jpeg|png|gif|gifv|svg))$/i.match(url))
            return cmd_title(m, url.sub($1, ''), false)
          end

          unless @silent_on_failure
            m.user.notice("Could not retrieve a valid title from #{uri.host}")
          end
        else
          unless @silent_on_failure
            m.user.notice('Sorry, I was unable to retrieve the title.')
          end
        end
      end

      def record_url(m, url)
        @last_recorded_url = url
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

        Nokogiri::HTML(html).at_css('head title').text
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
        response = RestClient.get(uri.to_s, {'User-Agent': @useragent})

        return false if response.code != 200

        response.body
      end

      def warn_user(m)
        if m.channel.opped?(m.user)
          Target("@" + m.channel.name).send("Tried to warn #{m.user.name} for re-using titles, but they were opped.")
          return
        end

        unless @warnings.key?(m.user)
          @warnings[m.user] = 0
        end

        @warnings[m.user] += 1
        message = "Please don't re-trigger the title command. (#{@warnings[m.user]}/4 times)"

        if @warnings[m.user] == 2
          m.user.notice(message)
        elsif @warnings[m.user] == 3
          m.channel.kick(m.user, message)
        elsif @warnings[m.user] == 4
          @warnings[m.user] = 0
          timeout_user(m, message + " [#{@warning_ban_duration} minute ban]")
        else
          m.reply("I'm sorry, Dave. I'm afraid I can't do that.")
        end
      end

      # @param [Message] m
      def timeout_user(m, reason)
        mask = m.user.mask('*!%u@%h')
        reason = reason % {
          nick: m.user.nick,
          user: m.user.user,
          host: m.user.host,
          channel: m.channel.name
        }

        m.channel.ban(mask)
        m.channel.kick(m.user, reason)

        Timer(@warning_ban_duration * 60, shots: 1) do
          m.channel.unban(mask)
        end
      end
    end
  end
end
