module VoiceBot
  module Plugin
    class AutoVoice
      include Cinch::Plugin

      def initialize(*args)
        super

        @autovoice = {}
        @idle = @bot.config.voice_idle * 60
        @modequeue = ModeQueue.new

        Timer(@bot.config.voice_timer, method: :check_voices)
        Timer(@bot.config.queue_timer, method: :check_queue)
      end

      listen_to :message, method: :on_message
      listen_to :quit, method: :on_quit
      listen_to :part, method: :on_part
      listen_to :voice, method: :on_voice
      listen_to :devoice, method: :on_devoice

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
      end

      match Regexp.new('autovoice (on|off|status|purge|debug)$'), method: :cmd_toggle_autovoice
      def cmd_toggle_autovoice(m, option)
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
                queue_devoice(m.channel, vuser)
              end
            end

            @autovoice.delete(m.channel)
            m.reply 'Autovoice for this channel has been turned off!'
          elsif option == 'status'
            status = @autovoice[m.channel] ? 'enabled' : 'disabled'
            m.reply "Autovoice setting for #{m.channel}: #{status}."
            m.reply "Global settings: Check every #{@bot.config.voice_timer} seconds for #{@bot.config.voice_idle} minutes of inactivity, processing the queue every #{@bot.config.queue_timer} seconds."
          elsif option == 'purge'
            affected = @autovoice[m.channel].count
            m.reply "Purging AutoVoice list. #{affected} users are affected."

            @autovoice[m.channel].each do |vusers|
              vusers.each do |vuser|
                queue_devoice(m.channel, vuser)
              end
            end

            @autovoice[m.channel] = []
          elsif option == 'debug' # TODO: && is not administrator
            debug @autovoice.to_s

            begin
              gist_url = Gist.gist(@autovoice[m.channel].to_s)['html_url']
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
              av_delete << {channel: channel, user: vuser.user}
            end
          end
        end

        av_delete.each do |hash|
          puts "Deleting #{hash.to_s}"
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
        remove(m.user) if enabled?(m.channel)
      end

      def on_part(m)
        remove(m.user, m.channel) if enabled?(m.channel)
      end

      def on_voice(m, user)
        unless find(user, m.channel)
          @autovoice[m.channel] << VoicedUser.new(user, m.channel, @idle)
        end
      end

      def on_devoice(m, user)
        remove(user, m.channel) if find(user, m.channel)
      end

      def autovoice(m)
        if m.channel.voiced?(m.user)
          search = find(m.user, m.channel)

          if search
            search.update_expiry(@idle)
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
          search = find(user, channel)

          @modequeue.append(channel, 'v', user, true) unless search
        end
      end

      def queue_devoice(channel, user)
        if voiced?(user, channel, false)
          search = find(user, channel)

          if search
            @modequeue.append(channel, 'v', user, false)
            remove(user, channel)
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
        av_copy = @autovoice

        @autovoice.each do |chan, vusers|
          if channel && channel == chan || !channel
            vusers.each do |vuser|
              if vuser.user == user
                debug "delete: found user #{vuser.user.nick} @ #{vuser.inspect}"
                av_copy[channel].delete(vuser)
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
