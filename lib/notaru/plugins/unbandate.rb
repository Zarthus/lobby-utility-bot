require 'time'

module Notaru
  module Plugin
    # TODO: Proper quiet support
    class UnbanDate
      include Cinch::Plugin

      listen_to :message, method: :on_message
      listen_to :notice, method: :on_message

      def initialize(*args)
        super

        prefix = @bot.config.plugins.prefix

        @match_regexp = Regexp.new("#{prefix}list (clearbans|clearquiets|unquiet|unban|help)(?: ([^ ]+))?")
        @unit_split_regexp = Regexp.new('(\d+)(hours|hour|h|days|day|d|weeks|week|w|months|month|m)')
      end

      def on_message(m)
        if m.channel && m.statusmsg_mode == 'o' && m.channel.opped?(m.user)
          match = @match_regexp.match(m.message)

          banlist_process(m, match) if match
        end
      end

      # @param [Message] m
      # @param [MatchData] match
      def banlist_process(m, match)
        if match[1] == 'help'
          m.reply(
            'Usage: list (clearbans | unban | help) [timeunit] -- ' \
                'timeunits: hours, days, weeks, months'
          )
          m.reply(
            'Only the commands \'un*\' supports timeunits. Timeunits is a string following <number><unit> format ' \
                '- i.e. 1d or 1w7h '
          )
        elsif match[1].start_with?('clear')
          info = if match[1] == 'clearbans'
                   banlist_process_unban_all(m.channel)
                 else # if match[1] == 'clearquiets'
                   banlist_process_unban_all(m.channel, true)
                 end

          m.reply("Unbanned #{info[:unbans]} hosts (Bans since #{info[:timespan]})")
        elsif match[1] == 'unquiet' || match[1] == 'unban'
          if match[2].nil?
            m.reply("Missing parameter 'timeunit' for #{match[1]}. See 'list help' for more information.")
            return
          end

          info = banlist_process_unban_timeunit(m.channel, match, match[1] == 'unquiet')
          m.reply("Unbanned #{info[:unbans]} hosts (Bans since #{info[:timespan]})")
        end
      end

      # @param [Channel] channel
      # @param [Boolean] quiets
      # @return [Hash]
      def banlist_process_unban_all(channel, quiets = false)
        len = channel.bans.length
        unban_list(channel, channel.bans, quiets)

        { unbans: len, timespan: 'the beginning of time' }
      end

      # @param [Channel] channel
      # @param [MatchData] match
      # @param [Boolean] quiets
      # @return [Hash]
      def banlist_process_unban_timeunit(channel, match, quiets = false)
        timespan = timespan_convert(match[2])
        log "Unbanning all users with a ban age of older than #{timespan} in #{channel}"
        int_timespan = timespan.to_i

        bans = []
        channel.bans.each do |host|
          bans << host if int_timespan > host.created_at.to_i
        end

        unban_list(channel, bans, quiets)

        { unbans: bans.length, timespan: timespan }
      end

      # @param [Channel] channel
      # @param [Array] bans
      # @param [Boolean] quiets
      def unban_list(channel, bans, quiets = false)
        hosts = []
        char = quiets ? 'q' : 'b'

        bans.each do |host|
          hosts << host

          if hosts.count > 3
            channel.mode('-' + (char * 4) + ' ' + hosts.join(' '))
            hosts = []
          end
        end

        unless hosts.empty?
          channel.mode('-' + (char * hosts.length) + ' ' + hosts.join(' '))
        end
      end

      # @param [String] timespan
      # @return [Time]
      def timespan_convert(timespan)
        units = {
          3600 => %i(h hour hours),
          86_400 => %i(d day days),
          604_800 => %i(w week weeks),
          2_592_000 => %i(m month months)
        }

        total = 0
        timespan.scan(@unit_split_regexp).each do |match|
          if match[0].to_i > 400 || total > 31_104_000
            log "Moving on early due to probable malformed input [match = #{match.inspect}, total = #{total}]"
            next
          end

          total += unit_convert(units, match[0], match[1])
        end

        Time.at(Time.now.to_i - total)
      end

      # @param [Hash] units
      # @param [Integer] amount
      # @param [String] unit
      # @return [Integer]
      def unit_convert(units, amount, unit)
        unit = unit.to_sym

        units.each do |k, v|
          return k * amount.to_i if v.include?(unit.to_sym)
        end

        0
      end
    end
  end
end
