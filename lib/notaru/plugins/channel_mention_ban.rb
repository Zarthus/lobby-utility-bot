require 'time'

module Notaru
  module Plugin
    class ChannelMentionBan
      include Cinch::Plugin

      # https://regex101.com/r/msRWP9/5
      CHANNEL_MENTION_REGEX = Regexp.new(/(?:\s|^)(#(?!\d+(?:\s+|\b|$))[\w\-.]+)(?:\s|\b|$)/)

      def initialize(*args)
          super

          @akick_base_duration = 12
          @akick_default_duration = 4
          @akick_after_warnings = 2
          @channels = ["#lobby"]
          @exempt = []
          @whitelist = ["#dragonweyr", "#help", "#lobby", "#coders"]
          @warnings = {}
          @format = "%{name}, please do not mention channels/hashtags/strings starting with '#' in %{channel}." +
            " Refer to https://lobby.lynvie.com/rules for the rules."
          @warn_clearance = (3 * 24 * 60 * 60)
          @keep = []
          @next_reset = newtime
      end

      match CHANNEL_MENTION_REGEX, method: :on_channel_mention, use_prefix: false
      match /mention(?: ([^ ]+)(?: ([^ ]+))?(?: ([^ ]+))?)?/, method: :cmd_chanmen

      def cmd_chanmen(m, command = nil, arg = nil, arg2 = nil)
        if command == nil
          return cmd_chanmen(m, 'help')
        end

        if m.channel.opped?(m.user)
          if command == 'help'
            return m.reply('Usage: !mention (help|clear|exempt|status|view|keep|unkeep|warn|unwarn)')
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
            m.reply("Default growing akick duration is #{@akick_default_duration}h, with a base of #{@akick_base_duration}h added to this. akicks will be issued after #{@akick_after_warnings} warnings.")
            m.reply("Warnings are cleared every #{@warn_clearance}s, warning format is: #{@format}, next reset cycle is at #{@next_reset.utc.iso8601}")
            return
          elsif command == 'view'
            return m.reply("Current warnings: #{@warnings.to_s}, keeping the warnings of: #{@keep.to_s}")
          elsif command == 'keep' || command == 'stick'
            @keep << arg
            m.reply("Keeping #{arg}'s warnings saved.")
          elsif command == 'unkeep' || command == 'unstick'
            if !@keep.include?(arg)
              return m.reply("Cannot unkeep #{arg}, they don't appear to be kept.")
            end
            @keep.delete(arg)
            m.reply("Unkept #{arg}")
          elsif command == 'warn'
              if arg.nil?
                return m.reply('Usage: !mention warn <nick> [amount = 1]')
              end
              amount = arg2.nil? ? 1 : arg2.to_i

              if @warnings.include?(arg)
                wcount = @warnings[arg] + amount
              else
                @warnings[arg] = 0
                wcount = amount
              end

              @warnings[arg] = @warnings[arg] + amount
              m.reply("Warning amount for #{arg} increased from #{@warnings[arg] - amount} to #{@warnings[arg]}")
          elsif command == 'unwarn'
            if arg.nil?
              return m.reply('Usage: !mention warn <nick> [amount = 1]')
            end
            amount = arg2.nil? ? 1 : arg2.to_i

            if !@warnings.include?(arg)
              return m.reply("User #{arg} has no warnings to speak of.")
            end

            if @warnings[arg] - amount < 0
              return m.reply("New warning count cannot be negative.")
            end

            @warnings[arg] = @warnings[arg] - amount
            m.reply("Warning amount for #{arg} decreased from #{@warnings[arg] + amount} to #{@warnings[arg]}")
          end
        end
      end

      def on_channel_mention(m, mentioned_channel)
        reset_warnings

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
          if mentioned_channel.downcase == chan.downcase
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
        duration_in_hours = duration_in_hours + @akick_base_duration

        if duration_in_hours > 120
            duration_in_hours = 120
        end

        Target("ChanServ").send("AKICK #{channel} ADD #{host} !T #{duration_in_hours}h #{reason}")
      end

      def reset_warnings
          unless Time.now > @next_reset
            return
          end

          info "Resetting warnings"
          info "old warnings: #{@warnings.to_s}"

          new_warns = {}
          @keep.each do |name|
              wcount = @warnings.include?(name) ? @warnings[name] : 0
              new_warns[name] = wcount
          end

          info "new warnings: #{new_warns.to_s}"
          @warnings = new_warns
      end

      def newtime
        Time.now + @warn_clearance
      end
   end
  end
end
