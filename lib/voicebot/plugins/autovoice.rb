module VoiceBot
  module Plugin
    class AutoVoice
      include Cinch::Plugin

      def initialize(*args)
        super

        @autovoice = {}
        @idle = @bot.config.voice_idle * 60
        @modequeue = ModeQueue.new

        @away_regexp = Regexp.new(@bot.config.name_away_regex)
        @smart_away = @bot.config.smart_away

        @away_modifier = (@bot.config.voice_idle / 5).ceil * 60
        @away_modifier = 180 if @away_modifier < 180

        Timer(@bot.config.voice_timer, method: :check_voices)
        Timer(@bot.config.queue_timer, method: :check_queue)
      end

      listen_to :message, method: :on_message
      listen_to :quit, method: :on_quit
      listen_to :kick, method: :on_kick
      listen_to :part, method: :on_part
      listen_to :voice, method: :on_voice
      listen_to :devoice, method: :on_devoice
      listen_to :op, method: :on_op
      listen_to :deop, method: :on_deop
      listen_to :nick, method: :on_user_state_change
      listen_to :away, method: :on_user_state_change

      timer 10, method: :on_init, shots: 1

      def on_init
        if @bot.config.channels.is_a?(String)
          info "Enabling autovoice for channel: #{@bot.config.channels}"
          @autovoice = { Channel(@bot.config.channels) => [] }
        else
          @bot.config.channels.each do |c|
            info "Enabling autovoice for channel: #{c}"
            @autovoice[Channel(c.to_s)] = []
          end
        end

        @autovoice.each do |chan, _|
          search_voices(chan)
        end
      end

      match Regexp.new('autovoice (on|off|status|purge|reset|debug)$'), method: :cmd_autovoice
      def cmd_autovoice(m, option)
        if m.channel.opped?(m.user)
          if option == 'on'
            if enabled?(m.channel)
              return m.reply 'Autovoice for this channel is already enabled!'
            end

            @autovoice[m.channel] = []
            m.reply 'Autovoice for this channel has been turned on!'
          elsif option == 'off'
            if disabled?(m.channel)
              return m.reply 'Autovoice for this channel is already disabled!'
            end

            @autovoice[m.channel].each do |vusers|
              vusers.each do |vuser|
                queue_devoice(m.channel, vuser, false)
              end
            end

            @autovoice.delete(m.channel)
            m.reply 'Autovoice for this channel has been turned off!'
          elsif option == 'status'
            status = @autovoice[m.channel] ? 'enabled' : 'disabled'
            m.reply "Autovoice setting for #{m.channel}: #{status}."

            gset = "Global settings: Check every #{bot.config.voice_timer} seconds for #{bot.config.voice_idle} minutes of inactivity, "
            gset += "Processing the queue every #{@bot.config.queue_timer} seconds. "
            gset += 'SmartAway is disabled.' unless @smart_away

            regexp_str = "or upon matching the '#{@bot.config.name_away_regex}' regex, " if @away_regexp

            gset += "On /away, #{regexp_str}" if @smart_away
            gset += "the users timer gets reduced to #{@away_modifier} seconds." if @smart_away

            if gset.length > 400
              gset = 'Global settings: ' + Gist.gist(gset)['html_url']
            end

            m.reply(gset)
          elsif option == 'purge'
            affected = @autovoice[m.channel].count
            m.reply "Purging AutoVoice list. #{affected} users are affected."

            @autovoice[m.channel].each do |vusers|
              vusers.each do |vuser|
                queue_devoice(m.channel, vuser)
              end
            end

            @autovoice[m.channel] = []
          elsif option == 'reset'
            # Send a debug print to the user.
            cmd_autovoice(m, 'debug')

            # Purges the list and see whom is voiced.
            @autovoice[m.channel] = []
            search_voices(m.channel)
          elsif option == 'debug' # TODO: && is not administrator
            dump = PP.pp(@autovoice, '')
            debug dump

            begin
              gist_url = Gist.gist(dump)['html_url']
              m.user.notice "Debug info: #{gist_url}"
            rescue StandardError => e
              m.reply "An error occurred while gisting contents. #{e}"
            end
          end
        end
      end

      match Regexp.new('devoiceme$'), method: :cmd_devoice_me
      def cmd_devoice_me(m)
        devoice(m)
      end

      def check_voices
        av_delete = []

        @autovoice.each do |channel, vusers|
          # To avoid an issue where by removing the users the number of iterations would go down, we clone it here.
          vusers_copy = vusers.clone
          vusers_copy.each do |vuser|
            if vuser.expired?
              queue_devoice(channel, vuser.user)
              av_delete << { channel: channel, user: vuser.user }
            end
          end
        end

        av_delete.each do |hash|
          debug "Deleting #{hash}"
          @autovoice[hash[:channel]].delete(hash[:user])
        end
      end

      def check_queue
        if @modequeue.count > 0
          debug "Processing the queue with #{@modequeue.count} entries."
        end

        @modequeue.execute(@bot)
      end

      def on_message(m)
        autovoice(m) if enabled?(m.channel)
      end

      def on_quit(m)
        remove(m.user)
      end

      def on_kick(m, user)
        remove(user, m.channel) if find(user, m.channel)
      end

      def on_part(m)
        remove(m.user, m.channel) if find(m.user, m.channel)
      end

      def on_voice(m, user)
        unless find(user, m.channel)
          @autovoice[m.channel] << VoicedUser.new(user, m.channel, @idle)
        end
      end

      def on_devoice(m, user)
        remove(user, m.channel) if find(user, m.channel)
      end

      def on_op(m, user)
        if user.nick == @bot.nick
          search_voices(m.channel) if enabled?(m.channel)
        end
      end

      def on_deop(m, user)
        if user.nick == @bot.nick
          if disabled?(m.channel) && @autovoice.key?(m.channel)
            log "Clearing #{m.channel.name}'s voice list from our records due to de-op.'"
            @autovoice[m.channel] = []
          end
        end
      end

      def on_user_state_change(m)
        if @smart_away && (@away_regexp.match(m.user.nick) || m.user.away)
          @autovoice.each do |chan, _|
            next unless enabled?(chan)

            found = find(m.user, chan)
            found.reduce_expiry_to(@away_modifier) if found
          end
        end
      end

      def autovoice(m)
        if m.channel.voiced?(m.user)
          search = find(m.user, m.channel)

          if search
            search.renew_expiry(@idle)
          else
            # The user is voiced, but not in our records.  Possibly a recovery from a crash or reboot. Or voiced by another op.
            log "User #{m.user.nick} seems to already be voiced, adding to records."
            @autovoice[m.channel] << VoicedUser.new(m.user, m.channel, @idle)
          end
        else
          queue_voice(m.channel, m.user)
          @autovoice[m.channel] << VoicedUser.new(m.user, m.channel, @idle)
        end
      end

      def queue_voice(channel, user)
        unless voiced?(user, channel, false)
          @modequeue.append(channel, 'v', user, true) unless @modequeue.find_param(user)
        end
      end

      def queue_devoice(channel, user, remove = true)
        if voiced?(user, channel, false)
          search = find(user, channel)

          if search
            @modequeue.append(channel, 'v', user, false)
            remove(user, channel) if remove
          end
        end
      end

      def search_voices(chan)
        if enabled?(chan)
          chan.users.each do |user, _data|
            if chan.voiced?(user) && !find(user, chan)
              log "Adding already voiced user #{user} to our records."
              @autovoice[chan] << VoicedUser.new(user, chan, @idle)
            end
          end
        end
      end

      def find(user, channel)
        @autovoice.each do |chan, vusers|
          if chan == channel
            vusers.each do |vuser|
              return vuser if vuser.user == user
            end
          end
        end
        false
      end

      def remove(user, channel = nil)
        av_copy = @autovoice.clone

        @autovoice.each do |chan, vusers|
          if channel && channel == chan || !channel
            vusers.each do |vuser|
              if vuser.user == user
                debug "delete: found user #{vuser.user.nick} @ #{vuser.inspect}"
                av_copy[chan].delete(vuser)
              end
            end
          end
        end

        @autovoice = av_copy
      end

      def voiced?(user, channel, strict = true)
        channel.voiced?(user) || (strict && find(user, channel))
      end

      def enabled?(channel)
        @autovoice.key?(channel) && channel.opped?(User(@bot.nick))
      end

      def disabled?(channel)
        !enabled?(channel)
      end
    end
  end
end
