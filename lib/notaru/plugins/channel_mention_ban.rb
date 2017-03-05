module Notaru
  module Plugin
    class ChannelMentionBan
      include Cinch::Plugin

      # https://regex101.com/r/msRWP9/5
      CHANNEL_MENTION_REGEX = Regexp.new(/(?:\s|^)(#(?!\d+(?:\s+|\b|$))[\w\-.]+)(?:\s|\b|$)/)

      def initialize(*args)
          super

          @akick_default_duration = 5
          @akick_after_warnings = 2
          @channels = ["#lobby"]
          @exempt = []
          @whitelist = ["#dragonweyr", "#help", "#lobby", "#coders"]
          @warnings = {}
          @format = "%{name}, please do not mention channels/hashtags/strings starting with '#' in %{channel}." +
            " Refer to https://lobby.lynvie.com/rules for the rules."
          @warn_clearance = 3600 * 12

          Timer(@warn_clearance) { @warnings = {} }
      end

      match CHANNEL_MENTION_REGEX, method: :on_channel_mention, use_prefix: false
      match /mention(?: ([^ ]+)(?: ([^ ]+))?)?/, method: :cmd_chanmen

      def cmd_chanmen(m, command = nil, arg = nil)
        if command == nil
          return cmd_chanmen(m, 'help')
        end

        if m.channel.opped?(m.user)
          if command == 'help'
            return m.reply('Usage: !mention (help|clear|exempt|status|view)')
          elsif command == 'clear'
            if !arg.nil? && !['warning', 'exempt'].include?(arg)
              return m.reply('Usage: !mention clear [warning|exempt]')
            end

            @warnings = {} if arg.nil? || arg == 'warning'
            @exempt = {} if arg.nil? || arg == 'exempt'

            m.reply("Cleared #{arg.nil? ? 'warnings and exemptions' : "#{arg}s"}")
          elsif command == 'exempt'
            return m.reply("Usage: !mention exempt h:hostname/n:nick/a:account") if arg.nil?

            safe_arg = arg.sub(/^h:|^n:|^a:/, '')

            to_push = nil
            if arg[0] == 'h'
              to_push = 'h:' + safe_arg
            elsif arg[0] == 'n'
              user = User(safe_arg)

              if user.nil?
                return m.reply("Cannot find nick #{safe_arg}")
              end

              to_push =  'h:' + user.mask('*!%u@%h').to_s
            elsif arg[0] == 'a'
              to_push = 'a:' + safe_arg.downcase
            else
              return m.reply("Usage: !mention exempt h:hostname/n:nick/a:account")
            end

            if @exempt.include?(to_push)
              return m.reply("This user [#{to_push}] is already exempted")
            end

            @exempt.push(to_push)
            m.reply("Added #{safe_arg} to my exemption list (lasts until reboot)")
          elsif command == 'status'
            m.reply("Monitoring channels: #{@channels.to_s}, whitelisted channels: #{@whitelist.to_s}, exempt users: #{@exempt.to_s}")
            m.reply("Default akick duration is #{@akick_default_duration}h, akicks will be issued after #{@akick_after_warnings} warnings.")
            m.reply("Warnings are cleared every #{@warn_clearance}s, warning format is: #{@format}")
            return
          elsif command == 'view'
            return m.reply("Current warnings: #{@warnings.to_s}")
          end
        end
      end

      def on_channel_mention(m, mentioned_channel)
        in_supported_channel = false
        @channels.each do |chan|
          if m.channel.name != chan
            debug "Channel mention is not in #{chan}"
            next
          end

          in_supported_channel = true
          break
        end

        unless in_supported_channel
          debug "Not in any supported channels, exiting."
          return
        end

        @whitelist.each do |chan|
          if mentioned_channel == chan
            debug "Channel mentioned [#{mentioned_channel}] is whitelisted"
            return
          end
        end

        uaddr = m.user.mask('%n!%u@%h')
        uauth = m.user.authed? ? m.user.authname.downcase : nil
        @exempt.each do |exempt|
          safe_arg = exempt.sub(/^h:|^a:/, '')
          type = exempt[0]

          if type == 'h' && uaddr == safe_arg
            debug "User #{m.user.name} is exempted under #{exempt}"
            return
          end

          if type == 'a' && uauth && uauth == safe_arg
            debug "User #{m.user.name} is exempted under #{exempt}"
            return
          end
        end

        if m.channel.opped?(m.user)
          return Target("@" + m.channel.name).send("User #{m.user.name} triggered channel-mentioning message, but was opped.")
        end

        debug "Caught channel in message: #{m.message}"
        warn_user(m)
      end

      def warn_user(m)
        to_warn = nil
        uaddr = nil
        text = @format % {
          channel: m.channel.name,
          name: m.user.name
        }

        m.user.refresh
        if m.user.authed?
          to_warn = m.user.authname.downcase
        else
          to_warn = m.user.name.downcase
        end
        uaddr = get_user_akick_address(m.user)

        if !@warnings.include?(to_warn)
          @warnings[to_warn] = 1
        else
          @warnings[to_warn] = @warnings[to_warn] + 1
        end

        uwarnings = @warnings[to_warn]

        if uwarnings >= @akick_after_warnings
          duration = uwarnings > @akick_after_warnings ? @akick_default_duration ** uwarnings : @akick_default_duration
          m.channel.kick(m.user, text)
          return akick_add(m.channel.name, uaddr, "Banned for #{duration} hours for repeatedly advertising channels. | #{m.message}", duration)
        end

        if m.channel.opped?(@bot)
          m.channel.kick(m.user, text)
        else
          m.reply(text)
        end
      end

      def get_user_akick_address(user)
        user.authed? ? user.authname.downcase : user.mask('*!%u@%h')
      end

      def akick_add(channel, host, reason, duration_in_hours = nil)
        duration_in_hours = @akick_default_duration if duration_in_hours.nil?

        Target("ChanServ").send("AKICK #{channel} ADD #{host} !T #{duration_in_hours}h #{reason}")
      end
    end
  end
end
