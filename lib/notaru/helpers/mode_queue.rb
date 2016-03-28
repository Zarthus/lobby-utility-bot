module Notaru
  class ModeQueue
    def initialize
      @queue = []
    end

    def append(target, mode, parameter = nil, add = true)
      @queue << { target: target, mode: mode, parameter: parameter, add: (add ? '+' : '-') }
    end

    def remove(item)
      @queue.remove(item)
    end

    def count
      @queue.count
    end

    def find_param(param)
      @queue.each do |h|
        return true if param == h[:parameter]
      end

      false
    end

    def empty
      @queue = []
    end

    def empty?
      @queue.count == 0
    end

    def parse(empty_queue = true)
      tpl = 'MODE %{target} %{modes} %{parameters}'
      modes = []

      str = ''
      params = ''
      mode_str = ''
      mode_ctx = nil
      target = nil
      iterations = 0

      @queue.each do |hash|
        if iterations == 0 # Reduce the number of times this gets checked for by 4.
          unless mode_ctx
            mode_ctx = hash[:add]
            mode_str += mode_ctx
          end

          target = hash[:target] unless target
        end

        if mode_ctx != hash[:add]
          mode_ctx = hash[:add]
          mode_str += mode_ctx
        end

        iterations += 1
        mode_str += hash[:mode]
        params = params + hash[:parameter].nick + ' '

        if target != hash[:target] || iterations > 3
          str = tpl % { target: target, modes: mode_str, parameters: params }

          if valid?(str)
            modes << str
          else
            puts "Invalid Mode String: #{str}" # This should never happen..
          end

          target = hash[:target]
          mode_str = ''
          params = ''
          iterations = 0
          mode_ctx = hash[:add]
          mode_str += mode_ctx
        end
      end

      if iterations != 0
        modes << tpl % { target: target, modes: mode_str, parameters: params }
      end

      empty if empty_queue

      modes
    end

    def execute(bot)
      return unless count != 0

      modes = parse false

      if modes
        modes.each do |perform|
          bot.irc.send perform
          sleep(0.5)
        end
      end

      empty
    end

    def valid?(str)
      regex = Regexp.new('MODE ([^ ]+) ([^ ]+)(?: (.*))?')
      match = str.split(regex)

      if match
        target = match[1]
        modes = match[2]
        params = match.count > 3 ? match[3] : nil

        return valid_target?(target) && valid_modes?(modes) && valid_params?(params)
      end

      false
    end

    def valid_target?(_target)  # TODO
      true
    end

    def valid_modes?(modes)
      ctx = nil
      last_char = nil
      iteration = 0

      modes.split('').each do |c|
        if c == '+' || c == '-'
          return false if last_char == '+' || last_char == '-'

          ctx = c
          last_char = c
          next
        end

        iteration += 1
        last_char = c
        return false unless ctx && iteration <= 4
      end
      true
    end

    def valid_params?(_params)  # TODO
      true
    end
  end
end
