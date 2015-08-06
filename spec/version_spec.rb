require 'rspec'
require_relative 'spec_helper'

describe VoiceBot do
  it 'should match a valid version' do
    expect(VoiceBot::VERSION).to match(/\d+\.\d+(\.\d+)?(\-[a-zA-Z])?/)
  end
end
