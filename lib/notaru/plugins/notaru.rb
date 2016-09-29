module Notaru
  module Plugin
    class Notaru
      include Cinch::Plugin

      match Regexp.new('notaru ([^ ]+)(?: (.+))?'), method: :cmd_notaru
      def cmd_notaru(m, command, params)
        if m.channel.opped?(m.user)
          if command == 'help'
            m.user.notice('Usage: notaru [help | docs | retainnick [newnick]]')
          elsif command == 'docs'
            m.reply('Notaru extended docs: https://github.com/Zarthus/lobby-utility-bot/wiki')
          elsif command == 'retainnick'
            m.reply(retainnick(params))
          end
        end
      end

      # @param [String] params
      # @return [String]
      def retainnick(params = nil)
        if params.nil?
          newnick = @bot.config.nick
 
          if newnick.nil?
            newnick = @bot.config.nicks.first
          end
        else
          return "Illegal parameters supplied." if /[ .@#!]/.match(params)
          newnick = params
        end
        
        if @bot.nick == newnick
          return "My name is already correct. (#{@bot.nick} == #{newnick})"
        end

        @bot.nick = newnick
        'Name has been changed.'
      end
    end
  end
end
