module Notaru
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
            c.nick = 'Notaru'
          end

          c.user = config['irc']['username'] || 'notaru'
          c.realname = config['irc']['realname'] || config['source_url'] || c.user

          c.local_host = config['irc']['bind'] if config['irc']['bind']

          if config['irc']['auth']['cert']['client_cert']
            c.ssl.client_cert = config['irc']['auth']['cert']['client_cert']
          elsif config['irc']['auth']['sasl']['account'] && config['irc']['auth']['sasl']['password']
            c.sasl.username = config['irc']['auth']['sasl']['account']
            c.sasl.password = config['irc']['auth']['sasl']['password']
          end

          c.channels = config['irc']['channels']

          c.prefix_char = Regexp.escape(config['prefix'])
          c.plugins.prefix = /^#{c.prefix_char}/
          c.plugins.plugins = [
            Plugin::AuthCheck,
            Plugin::AutoVoice,
            Plugin::ChannelMentionBan,
            Plugin::CoreCTCP,
            Plugin::Conversion,
            Plugin::Quotes,
            Plugin::SecretAdmin,
            Plugin::Title,
            Plugin::UnbanDate,
            # Plugin::Shorten,
            Plugin::Notaru
          ]

          c.source_url = config['source_url'] if config['source_url']

          c.title_format = config['plugin']['title']['format'] || 'Title: \'%{title}\' at %{host}'
          c.title_ignore = config['plugin']['title']['ignore'] || []
          c.title_silent_on_fail = config['plugin']['title']['silent_on_failure']

          c.authcheck_channels = config['plugin']['authcheck']['channels'] || []
          c.authcheck_masks = config['plugin']['authcheck']['masks'] || []
          c.authcheck_kick_first = config['plugin']['authcheck']['kick_first'].nil? ? true : config['plugin']['authcheck']['kick_first']
          c.authcheck_timeout = config['plugin']['authcheck']['timeout'] || 180
          c.authcheck_reason_format = (config['plugin']['authcheck']['reason_format'] || 'You need to be ' \
              'authenticated with NickServ to join %{channel}, ' \
              'see \'/msg NickServ HELP REGISTER\' for more information.')

          c.voice_timer = config['plugin']['autovoice']['voice_timer_interval'] || 60
          c.voice_idle = config['plugin']['autovoice']['voice_minute_idle'] || 60
          c.queue_timer = config['plugin']['autovoice']['voice_queue_timer'] || 5
          c.name_away_regex = config['plugin']['autovoice']['name_away_regex']

          alt_storage = File.join(Dir.back(c.root, 2), 'storage')
          c.smart_away = config['plugin']['autovoice']['smart_away']
          c.storage = File.join(config['storage_path'] || alt_storage)
          c.plugins.options[Plugin::Quotes] = { quotes_file: File.join(__dir__, '/../../conf/quotes.yml'),
                                                quotes_url: config['plugin']['quotes']['url'] }
        end
      end
    end
  end
end
