#!/usr/bin/env ruby

$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/lib")

require 'voicebot/voicebot'

if Process.uid == 0 && RUBY_PLATFORM !~ /mswin|mingw|cygwin/
  puts 'Please do not start this program as root.'
  exit 1
end

bot = VoiceBot::VoiceBot.new
bot.start
