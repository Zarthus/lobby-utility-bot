require 'time'
require 'cinch'
require 'yaml'
require 'cgi'

module Notaru
  module Plugin
    class Quotes
      include Cinch::Plugin

      match Regexp.new('(?:addquote|quoteadd) (.+)', Regexp::IGNORECASE), method: :addquote
      match Regexp.new('quote(?: (.+))?\s*$', Regexp::IGNORECASE), method: :quote
      match Regexp.new('quotes\s*$', Regexp::IGNORECASE), method: :quotecount
      match Regexp.new('(?:delquote|quotedel|undelquote|quoteundel) (\d+)', Regexp::IGNORECASE), method: :delquote

      def initialize(*args)
        super

        @quotes_file = config[:quotes_file]
        @quotes_url = config[:quotes_url]
      end

      def addquote(m, quote)
        if m.channel && !m.channel.opped?(m.user) && !m.user.authed?
          return m.reply("Only channel ops and registered users can add quotes.")
        end

        # make the quote
        new_quote = { 'quote' => quote,
                      'added_by' => m.user.authed? ? m.user.authname : m.user.nick,
                      'channel' => m.channel.name,
                      'created_at' => Time.now.utc,
                      'deleted' => false }

        # add it to the list
        existing_quotes = retrieve_quotes || []
        existing_quotes << new_quote

        # find the id of the new quote and set it based on where it was placed in the quote list
        new_quote_index = existing_quotes.index(new_quote)
        existing_quotes[new_quote_index]['id'] = new_quote_index + 1

        # write it to the file
        output = File.new(@quotes_file, 'w')
        output.puts YAML.dump(existing_quotes)
        output.close

        # send reply that quote was added
        m.reply "#{m.user.nick}: Quote successfully added as \\#{new_quote_index + 1}."
      end

      def delquote(m, quote_id)
        if !m.channel || !m.channel.opped?(m.user)
          return m.reply('You need to be a channel op to remove or restore quotes.')
        end

        existing_quotes = retrieve_quotes || []
        target_quote = existing_quotes.clone.delete_if { |q| q['id'] != quote_id.to_i }

        if target_quote.empty?
          return m.reply('No quote with that ID found.')
        end

        if target_quote.size > 1
          return m.reply('Somehow, more than one result was found. @_@')
        end

        target_quote = target_quote.first

        if target_quote['channel'] != m.channel.name
          return m.reply('Channel mismatch, you must delete quotes in the channel they were added in.')
        end

        target_quote['deleted'] = !target_quote['deleted']
        idx = existing_quotes.find_index { |q| q['id'] == target_quote['id'] }

        if idx.nil?
          return m.reply('Failed to alter quote database.')
        end

        existing_quotes[idx] = target_quote
        output = File.new(@quotes_file, 'w')
        output.puts YAML.dump(existing_quotes)
        output.close

        m.reply('Successfully ' + (target_quote['deleted'] ? 'deleted' : 'restored') + ' quote ID ' + target_quote['id'].to_s)
      end

      def quotecount(m)
        qret = retrieve_quotes()
        del_count = qret.reject { |q| !q['deleted'] }.size
        chan_count = qret.reject { |q| q['channel'] != m.channel.name }.size
        highest_idx = 0
        qidx = qret.each do |q| 
          if q["id"] > highest_idx
            highest_idx = q["id"]
          end
        end

        m.reply("Quotes: #{qret.size()} quotes are found, of which #{del_count} are deleted, and #{chan_count} from this channel." +
                " The latest quote to be added is ID \\#{highest_idx}")
      end

      def quote(m, search = nil)
        quotes = retrieve_quotes.delete_if { |q| q['deleted'] == true }
        if search.nil? # we are pulling random
          quote = quotes.sample
          m.reply "#{m.user.nick}: \\#{quote['id']} - #{fmt_quote(quote['quote'])}"
        elsif /^\d+$/.match(search) && search.to_i != 0 # then we are searching by id
          quote = quotes.find { |q| q['id'] == search.to_i }
          if quote.nil?
            m.reply "#{m.user.nick}: No quotes found."
          else
            m.reply "#{m.user.nick}: \\#{quote['id']} - #{fmt_quote(quote['quote'])}"
          end
        else
          quotes.keep_if { |q| q['quote'].downcase.include?(search.downcase) }
          if quotes.empty?
            m.reply "#{m.user.nick}: No quotes found."
          else
            quote = quotes.first
            m.reply "#{m.user.nick}: \\#{quote['id']} - #{fmt_quote(quote['quote'])}"
            if quotes.size > 20 && @quotes_url
              m.reply "Too many results (#{quotes.size}) found while searching for more, view them here: " + @quotes_url + "?search=" + CGI.escape(search)
            elsif quotes.size > 3 && @quotes_url
              m.reply "#{quotes.size - 1} more results, view them here: " + @quotes_url + "?quotes=" + quotes.map { |q| q['id'] }.join(',')
            elsif quotes.size > 1
              m.reply "The search term also matched on quote IDs: " + quotes.map { |q| q['id'] }.join(', ').sub(quote['id'].to_s + ', ', '')
            end
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Protected
      #--------------------------------------------------------------------------------

      protected

      def retrieve_quotes
        output = File.new(@quotes_file, 'r')
        quotes = YAML.load(output.read)
        output.close

        quotes
      end

      def fmt_quote(quote)
        new_quote = quote
        userlist = @bot.user_list.sort_by { |x| x.nick.length }
        
        userlist.each do |user|
          if new_quote.include?(user.nick)
            repl = user.nick.gsub("", "\u200D")
            log "quote: found name #{user.nick}, replacing with ZWS"
            new_quote.gsub!(user.nick, repl)
          end
        end

        return new_quote
      end
    end
  end
end
