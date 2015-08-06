require 'voicebot/includes'

module VoiceBot
  class VoiceBot
    def initialize
      @bot = Configuration.parse

      logfile = storage(File.join('logs', 'irc.log'))
      @bot.loggers << Cinch::Logger::FormattedLogger.new(File.open(logfile, 'w+'))
    end

    def start
      @bot.start
    end

    def storage(path = nil)
      return File.join(@bot.config.storage, path) if path

      @bot.config.storage
    end
  end
end
