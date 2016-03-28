require 'rspec'
require_relative 'spec_helper'

describe Notaru do
  it 'should match a valid version' do
    expect(Notaru::VERSION).to match(/\d+\.\d+(\.\d+)?(\-[a-zA-Z])?/)
  end
end
