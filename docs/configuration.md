```
irc.server: String, the irc server.
irc.server_password: Optional String, the password of the irc server
irc.port: Integer, the port to connect to
irc.ssl: Boolean, connect with SSL or not
irc.ssl_verify: Boolean, verify ssl certificate
irc.bind: String, host to bind to
irc.umodes: String, modes to set on connecting

irc.realname: String, realname
irc.username: String, username / ident, negated if an identd is installed
irc.nick: String, nickname to use

irc.auth.cert.client_cert: String, path to irc client certificate to authenticate with

irc.auth.sasl.account: String, accountname with Services
irc.auth.sasl.password: String, password to identify with

irc.channels: Array, list of strings of channels to join and autovoice in by default

plugin.autovoice.voice_timer_interval: Integer, how often, in seconds, do we check if voices are expired?
plugin.autovoice.voice_minute_idle: Integer, how many minutes does an user need to idle to be devoiced
plugin.autovoice.voice_queue_timer: Integer, how often, in seconds, do we clear the queue?
plugin.autovoice.smart_away: Boolean, do we reduce the timer when an user goes /away or matches name_away_regex?
plugin.autovoice.name_away_regex: Boolean false or String Regular Expression, matches nicks that are detected as 'away'

plugin.title.format: String, dynamic content is wrapped in %{}, supported values: title, url, host, nick
plugin.title.ignore: Array, list of domains to ignore
plugin.title.silent_on_failure: Boolean, true if you want the bot to not notice the user on failure

logging: Boolean, log to file or not?
prefix: String char, what is the prefix to our commands?
source_url: Optional String, if the project is open source, you can put an URL to its location here.
```
