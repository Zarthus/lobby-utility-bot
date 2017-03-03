module Notaru
  module Plugin
    class Conversion
      include Cinch::Plugin

      # https://regex101.com/r/KVu6rR/1
      TEMPERATURE_REGEX = Regexp.new(/(?<amount>-?\d{1,8}(?:\.\d{1,8})?)[^\S\n]*(?<degrees>°|deg(?:rees?)?|in)?[^\S\n]*(?<unit>c(?:(?=el[cs]ius\b|entigrades?\b|\b))|f(?:(?=ahrenheit\b|\b))|k(?:(?=elvins?\b|\b)))/i)

      DEGR = "°"

      def initialize(*args)
          super
          @stored_temperature = nil
      end

      match /!c(?:onvert)?(?: (.*))?/, method: :convert_temperature_from_message, use_prefix: false
      match /murica(?: (.*))?/, method: :convert_temperature_from_message
      match TEMPERATURE_REGEX, method: :store_temperature, use_prefix: false
      match /di(?:stance)? (?<amount>\d{1,12})\s*(?<unit>km|mi|kilometers|miles)/i, method: :convert_distance

      def store_temperature(m, amount, degrees, unit)
          debug "Caught temperature in message: #{m.message}"
          debug "Values: amount=#{amount}, degrees=#{degrees}, unit=#{unit}"
          @stored_temperature = m.message
      end

      def convert_temperature_from_message(m, message)
          if message && TEMPERATURE_REGEX =~ message || @stored_temperature && TEMPERATURE_REGEX =~ @stored_temperature
              @stored_temperature = nil
              return convert_temperature(m, $1, $2, $3)
          end

          m.user.notice("Unable to parse message as valid temperature. (@stored_temperature = #{@stored_temperature.inspect})")
      end

      def convert_distance(m, amount, unit)
          amount = amount.to_f
          unit.downcase!
          return m.reply("Invalid unit.") unless ['mi', 'km', 'miles', 'kilometers'].include?(unit)

          unit = "mi" if unit == "miles"
          unit = "km" if unit == "kilometers"
          other_unit = unit == "mi" ? "km" : "mi"

          mth = "#{unit}_#{other_unit}".to_sym
          result = method(mth).call(amount)

          m.reply("#{round_to(amount, 2)}#{unit} is equal to #{result}#{other_unit}")
      end

      def convert_temperature(m, amount, degrees, unit)
          amount = amount.to_f
          unit.downcase!
          if unit == 'c'
              m.reply("%s%sC is %s%sF (or %sK)" % [
                  round_to(amount, 2), DEGR, c_f(amount), DEGR, c_k(amount)
              ])
          elsif unit == 'f'
              m.reply("%s%sF is %s%sC (or %sK)" % [
                  round_to(amount, 2), DEGR, f_c(amount), DEGR, f_k(amount)
              ])
          else
              m.reply("%sK is %s%sC (or %s%sF)" % [
                  round_to(amount, 2), k_c(amount), DEGR, k_f(amount), DEGR
              ])
          end
      end

      def c_f(amount)
          round_to(amount * 1.8 + 32, 2)
      end

      def c_k(amount)
          round_to(amount + 273.15, 2)
      end

      def f_c(amount)
          round_to((amount - 32) * 5 / 9, 2)
      end

      def f_k(amount)
          round_to((amount + 459.67) * 5 / 9, 2)
      end

      def k_c(amount)
          round_to(amount - 273.15, 2)
      end

      def k_f(amount)
          round_to(1.8 * (amount - 273) + 32, 2)
      end

      def km_mi(amount)
          round_to(amount * 0.6213, 2)
      end

      def mi_km(amount)
          round_to(amount * 1.609, 2)
      end

      def round_to(value, pos = 2)
          return value.to_i if (value.abs - value.abs.floor).zero?

          "%.#{pos}f" % value
      end
    end
  end
end
