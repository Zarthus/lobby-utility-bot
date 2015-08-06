module VoiceBot
  class VoicedUser
    def initialize(user, channel, expiry)
      @expiry = VoiceExpiry.new(expiry)
      @user = user
      @channel = channel
    end

    def update_expiry(expiry)
      @expiry.renew(expiry)
    end

    attr_reader :user
    attr_reader :channel
    attr_reader :expiry

    def expired?
      @expiry.expired?
    end

    def inspect
      "#<VoicedUser @expiry=#{@expiry.inspect} @channel=#{@channel.inspect} @user=#{@user.inspect}>"
    end
  end
end
