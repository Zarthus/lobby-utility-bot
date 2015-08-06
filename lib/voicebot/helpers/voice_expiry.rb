module VoiceBot
  class VoiceExpiry
    # A margin to make devoicing feel smoother
    # Users who talk at the same time might not get devoiced at the same time due to a second offset.
    # This fixes that.
    MARGIN = 4

    def initialize(expiry)
      @expiry = Time.now.to_i + expiry.to_i
    end

    def renew(expiry)
      @expiry = Time.now.to_i + expiry.to_i
    end

    def expired?
      @expiry - MARGIN <= Time.now.to_i
    end

    def to_s
      Time.at(@expiry).to_datetime
    end

    def inspect
      "#<VoiceExpiry expiry=#{@expiry}>"
    end
  end
end
