module VoiceBot
  class VoiceExpiry
    # A margin to make devoicing feel smoother
    # Users who talk at the same time might not get devoiced at the same time due to a second offset.
    # This fixes that.

    def initialize(expiry, margin = 30)
      @expiry = Time.now.to_i + expiry.to_i
      @margin = margin
    end

    def reduce_to(expiry)
      return if Time.now.to_i + expiry.to_i > @expiry

      @expiry = Time.now.to_i + expiry.to_i
    end

    def renew(expiry)
      @expiry = Time.now.to_i + expiry.to_i
    end

    def expired?
      @expiry - @margin <= Time.now.to_i
    end

    def seconds
      @expiry - (@margin + Time.now.to_i)
    end

    def to_s
      Time.at(@expiry).to_datetime
    end

    def inspect
      "#<VoiceExpiry expiry=#{@expiry} in=\"#{seconds}s\">"
    end
  end
end
