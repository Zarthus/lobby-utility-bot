module Notaru
  module Plugin
    # A note:
    #
    # Quiets are not present on every network, but the bot does still support setting them regardless,
    # and assumes competent channel moderation. In addition, on networks where it means 'owner', the bot
    # generally does not have sufficient permissions to set the mode regardless.
    #
    # Commands are triggered through STATUSMSG (/notice @#channel !k [host/nick]), not every network supports this.
    class SecretAdmin
      def initialize(*args)
        super

        prefix = @bot.config.plugins.prefix
        # Due to priority, avoid conflicts - longer strings should come first.
        @match_regexp = Regexp.new(
          "#{prefix}(kick|kickban|ban|unban|quiet|unquiet|kb|ub|uq|k|q|b)(?: ([^ ]+))?(?: (.*))?"
        )
        @match_map = {
          kick: %i(k kick),
          ban: %i(b ban),
          kickban: %i(kb kickban),
          quiet: %i(q quiet),
          unban: %i(ub unban),
          unquiet: %i(uq unquiet)
        }
      end

      include Cinch::Plugin

      listen_to :message, method: :on_message
      listen_to :notice, method: :on_message

      def on_message(m)
        if m.channel && m.statusmsg_mode == 'o' && m.channel.opped?(m.user)
          match = @match_regexp.match(m.message)

          if match
            name = match_name_to_s(match[1])

            if %i(kick kickban ban quiet unban unquiet).include?(name)
              unless m.channel.opped?(@bot.nick)
                m.reply("I need to be opped in the channel to perform any administrative actions (like '#{name}')")
                return
              end

              action_admin_generic(m, match, name)
            end
          end
        end
      end

      # @param [Message] m
      # @param [MatchData] match with 0=full_match; 1=name_short; 2=target; 3=optional_reason
      # @param [String] name
      def action_admin_generic(m, match, name)
        if match.length <= 2 || match[2].nil? || match[2].empty?
          m.reply("Error: Action '#{name}' requires secondary parameter 'nick'" + (name != :kick ? " or 'host'" : ''))
          return
        end

        chars = match[2].split('')

        if chars.include?('@') || chars.include?('!')
          user = nil
        else
          begin
            user = User(match[2])
          rescue StandardError => e
            m.reply("Aborting due to error when finding user [#{match[2]}]: #{e}")
            return
          end
        end

        if user && !user.nil?
          if m.channel.opped?(user)
            m.reply("Error: Action '#{name}' cannot be executed on channel staff.")
            return
          end

          begin
            mask = user.mask('*!*@%h')
          rescue NoMethodError
            m.reply("Warning: User hostmask not found, if you want to #{name} a mask use '#{match[2]}!*@*' instead")
            return
          end
        else

          if name == :kick || (!chars.include?('!') && !chars.include?('@'))
            m.reply("Error: Action '#{name}' - secondary parameter '#{match[2]}' not found")
            return
          end

          mask = match[2]
        end

        m.channel.ban(mask) if name == :kickban || name == :ban
        m.channel.unban(mask) if name == :unban
        m.channel.mode("+q #{mask}") if name == :quiet
        m.channel.mode("-q #{mask}") if name == :unquiet

        reason = match.length > 3 ? match[3] : nil
        if %i(kick kickban).include?(name)
          if reason.nil? || reason.empty?
            m.channel.kick(user, 'Your behaviour is not conducive to the desired environment.')
          else
            m.channel.kick(user, reason)
          end
        end
      end

      # @param [String] name
      # @return [Symbol, nil]
      def match_name_to_s(name)
        name = name.downcase.to_sym

        @match_map.each do |k, v|
          return k if v.include?(name)
        end

        nil
      end
    end
  end
end
