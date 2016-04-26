module Notaru
  module Plugin
    class Notaru
      include Cinch::Plugin

      match Regexp.new('notaru ([^ ]+)'), method: :cmd_notaru
      def cmd_notaru(m, command)
        if m.channel.opped?(m.user)
          if command == 'help'
            m.user.notice('Usage: notaru [help | docs | retainnick]')
          elsif command == 'docs'
            m.reply('Notaru extended docs: https://github.com/Zarthus/lobby-utility-bot/wiki')
          elsif command == 'retainnick'
            m.reply(retainnick)
          end
        end
      end

      # @return [String]
      def retainnick
        newnick = @bot.config.nick

        if newnick.nil?
          newnick = @bot.config.nicks.first
        end

        if @bot.nick == newnick
          return 'My name is already correct.'
        end

        @bot.nick = newnick
        'Name has been changed.'
      end
    end
  end
end
