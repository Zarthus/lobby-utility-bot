module VoiceBot
  class Configuration
    def self.parse
      Cinch::Bot.new do
        configure do |c|
          c.root = __dir__

          config_file = './conf/config.yml'
          fail "Initial configuration file '#{config_file}' does not exist." unless File.exist?(config_file)

          config = YAML.load_file(config_file)

          c.server = config['irc']['server']
          if config['irc']['server_password']
            c.password = config['irc']['server_password']
          end

          c.port = config['irc']['port'] || 6667
          c.ssl.use = config['irc']['ssl']
          c.ssl.verify = config['irc']['ssl_verify']

          c.modes = config['irc']['umodes'].chars if config['irc']['umodes']

          if config['irc']['nick']
            c.nick = config['irc']['nick']
          elsif config['irc']['nicks']
            c.nicks = config['irc']['nicks']
          else
            c.nick = 'VoiceBot'
          end

          c.user = config['irc']['username'] || 'voicebot'
          c.realname = config['irc']['realname'] || config['source_url'] || c.user

          c.local_host = config['irc']['bind'] if config['irc']['bind']

          if config['irc']['auth']['cert']['client_cert']
            c.ssl.client_cert = config['irc']['auth']['cert']['client_cert']
          elsif config['irc']['auth']['sasl']['account'] && config['irc']['auth']['sasl']['password']
            c.sasl.username = config['irc']['auth']['sasl']['account']
            c.sasl.password = config['irc']['auth']['sasl']['password']
          end

          c.channels = config['irc']['channels']

          c.plugins.prefix = /^#{Regexp.escape(config['prefix'])}/
          c.plugins.plugins = [Plugin::AutoVoice, Plugin::CoreCTCP]

          c.source_url = config['source_url'] if config['source_url']

          c.voice_timer = config['plugin']['autovoice']['voice_timer_interval'] || 60
          c.voice_idle = config['plugin']['autovoice']['voice_minute_idle'] || 60
          c.queue_timer = config['plugin']['autovoice']['voice_queue_timer'] || 5

          alt_storage = File.join(Dir.back(c.root, 2), 'storage')
          c.storage = File.join(config['storage_path'] || alt_storage)
        end
      end
    end
  end
end
