require_relative 'kite_connect'
require_relative 'kite_ticker'
require_relative 'feeder'
require_relative 'bar'
require_relative 'strategy_highlow'
require_relative 'strategy_bigcandle'
require 'frappuccino'
require 'logger'
require 'yaml'

CONFIG = OpenStruct.new YAML.load_file 'config/config.yaml'

APP=Logger.new('logs/app.log', 'daily', 30)
DATA=Logger.new('logs/data.log')
LOG1=Logger.new('logs/strategy1.log', 'daily', 30)
LOG2=Logger.new('logs/strategy2.log', 'daily', 30)

APP.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

LOG1.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end


LOG2.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

DATA.formatter = proc do |severity, datetime, progname, msg|
    "#{msg}\n"
end

kite_connect = KiteConnect.new(CONFIG.api_key,APP)

unless CONFIG.access_token.nil?
  kite_connect.set_access_token(CONFIG.access_token)
  APP.info "Using ACCESS TOKEN From Database"
else
  APP.info kite_connect.generate_access_token(CONFIG.request_token, CONFIG.api_secret)
  APP.info "Updating ACCESS TOKEN in Database"
  CONFIG[:access_token] = kite_connect.access_token
  File.open('config/config.yaml', 'w') {|f| f.write CONFIG.to_yaml }
end

kite_ticker = KiteTicker.new(kite_connect.access_token,kite_connect.api_key,APP)
feeder = Feeder.new(kite_ticker,DATA)

strategy1 = StrategyHighLow.new(kite_connect, feeder,LOG1)
strategy2 = StrategyBigCandle.new(kite_connect, feeder, LOG2) 
feeder.start

#LOG.info kite_connect.ltp("15111682")
#LOG.info kite_connect.ltp("15109890")
