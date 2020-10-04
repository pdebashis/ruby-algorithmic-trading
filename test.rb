require_relative 'kite_connect'
require_relative 'kite_ticker'
require_relative 'feeder'
require_relative 'bar'
require_relative 'strategy_highlow'
require_relative 'strategy_bigcandle'
require_relative 'strategy_eliminate_sl'
require_relative 'strategy_early_target'
require 'frappuccino'
require 'logger'
require 'yaml'

CONFIG = OpenStruct.new YAML.load_file 'config/config.yaml'

APP=Logger.new('logs/app.log')
DATA=Logger.new('logs/data.log')
LOG1=Logger.new('logs/strategy_highlow.log', 'daily', 30)
LOG2=Logger.new('logs/strategy_early_target.log', 'daily', 30)
LOG3=Logger.new('logs/strategy_eliminate_sl.log', 'daily', 30)
LOG4=Logger.new('logs/strategy_bigcandle.log', 'daily', 30)

APP.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

DATA.formatter = proc do |severity, datetime, progname, msg|
    "#{msg}\n"
end

log_formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

LOG1.formatter = log_formatter 
LOG2.formatter = log_formatter
LOG3.formatter = log_formatter
LOG4.formatter = log_formatter

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
feeder = Feeder.new(kite_ticker,DATA,260105)

strategy1 = StrategyHighLow.new(kite_connect, feeder,LOG1)
strategy2 = StrategyEarlyTarget.new(kite_connect, feeder, LOG2)
strategy3 = StrategyEliminateSL.new(kite_connect, feeder, LOG3)
strategy4 = StrategyBigCandle.new(kite_connect, feeder, LOG4)
feeder.start
