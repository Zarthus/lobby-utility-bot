
module Notaru
  module Plugin
    class AuthCheck
      include Cinch::Plugin

      def initialize(*args)
        super

        @channels = @bot.config.authcheck_channels
        @masks = []
        @bot.config.authcheck_masks.each do |mask|
          @masks << Cinch::Mask.from(mask)
        end

        @kick_first = @bot.config.authcheck_kick_first
        @timeout = @bot.config.authcheck_timeout
        @reason = @bot.config.authcheck_reason_format
        @kicked = []
        @exempt = []
      end

      listen_to :join, method: :on_join

      # @param [Message] m
      def on_join(m)
        return unless @channels.include?(m.channel.name)
        return unless m.channel.opped?(@bot)
        return unless matches?(m.user.mask)

        m.user.refresh

        return unless m.user.authname.nil?

        timeout_user(m)
      end

      # <@Zarthus> i'm thinking of adding a way to circumvent the authcheck for regulars
      # <@Zarthus> like '/msg notaru !authcheck bypass' -- only something regulars will remember.
      # <@Stomach> That's about four too many words :(
      # <@Zarthus> so what do you suggest
      # <@Stomach> Something like !butt
      # <@Stomach> That's easy to remember
      match Regexp.new('butts?'), method: :bypass
      match Regexp.new('authcheck ([^ ]+)(?: ([^ ]+))?'), method: :authcheck
      def authcheck(m, command, option = nil)
        if m.channel.nil? && command == 'bypass'
          return bypass(m)
        end

        return unless @channels.include?(m.channel.name)

        unless m.channel.opped?(m.user)
          m.user.notice('You need to be a channel op to use this command.')
        end

        if command == 'exempt'
          unless option
            m.reply('error: authcheck-exempt requires a secondary parameter (the users hostmask)')
            return
          end

          begin
            @exempt << Cinch::Mask.from(option)
            m.reply("The mask '#{option}' has been exempted. This is a temporary action.")
          rescue NoMethodError => e
            m.reply('The mask could not be exempted (did you enter a valid hostmask?)')
            info("Failed to exempt mask (may not be an error): #{e}")
          end
        elsif command == 'info'
          exmpt = @exempt.join(', ')
          msks = @masks.join(', ')

          exmpt = exmpt.empty? ? 'none' : exmpt
          msks = msks.empty? ? 'none' : msks

          m.reply('Banned masks: ' + msks + ' | Exempted masks (preserved until shutdown): ' + exmpt)
          m.reply((@kick_first ? "First time will be a kick, second violation will result in ban" : "User will be banned") +
		" for " + timeout_to_s)
          unless m.channel.opped?(@bot)
            m.reply('Note: I need to be opped in this channel to function.')
          end
        else
          m.reply('AuthCheck Commands: info - returns the configured options | exempt <hostmask> - exempts a hostmask')
        end
      end

      # @param [User] user
      # @return [Boolean]
      def matches?(user)
        return false if exempt?(user)

        @masks.each do |mask|
          next unless mask.match(user)

          return true
        end

        false
      end

      # @param [User] user
      # @return [Boolean]
      def exempt?(user)
        @exempt.each do |mask|
          next unless mask.match(user)

          return true
        end

        false
      end

      # @param [Message] m
      def timeout_user(m)
        mask = m.user.mask('*!%u@%h')
        reason = @reason % {
          nick: m.user.nick,
          user: m.user.user,
          host: m.user.host,
          channel: m.channel.name
        }

        if @kick_first && !@kicked.include?(mask)
          @kicked = [] if @kicked.count > 10

          @kicked << mask
          m.channel.kick(m.user, reason)
          return
        end

        m.channel.ban(mask)
        m.channel.kick(m.user, reason)
        m.user.msg(
          "You have been banned from #{m.channel.name} for #{timeout_to_s} because you need to be " \
          'logged in to enter this channel. Please authenticate before rejoining.'
        )

        Timer(@timeout, shots: 1) do
          m.channel.unban(mask)
        end
      end

      # @return [String]
      def timeout_to_s
        minutes = @timeout / 60

        return "#{minutes} minutes" if minutes > 1

        "#{@timeout} seconds"
      end

      def bypass(m)
          @exempt << Cinch::Mask.from(m.user)
          m.reply("You're now bypassing the authcheck filter.")
      end
    end
  end
end
