require_relative 'lib/kite/kite_connect'
require_relative 'lib/kite/kite_ticker'
require_relative 'lib/feeder'
require_relative 'lib/bar'
require_relative 'lib/strategy/highlow'
require_relative 'lib/strategy/bigcandle'
require_relative 'lib/telegram/bot'
require 'frappuccino'
require 'logger'
require 'yaml'

APP=Logger.new('logs/app.log')
DATA=Logger.new('logs/data.log')
LOG1=Logger.new('logs/strategy_highlow.log', 'daily', 30)
LOG2=Logger.new('logs/strategy_eliminate_sl.log', 'daily', 30)

APP.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

DATA.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")  
  "[#{date_format}] #{msg}\n"
end

log_formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

LOG1.formatter = log_formatter 
LOG2.formatter = log_formatter

traders=[]

CLIENTS=YAML.load_file 'config/login.yaml'
CLIENTS.each do |client|
  kite_connect = KiteConnect.new(client[:api_key],APP)

  unless client[:access_token].nil?
    kite_connect.set_access_token(client[:access_token])
    APP.info "Using ACCESS TOKEN From Database"
  else
    login_details=kite_connect.generate_access_token(client[:request_token], client[:api_secret])
    APP.info "Updating ACCESS TOKEN in Database"
    client[:access_token] = kite_connect.access_token
    client[:login_time] = login_details["login_time"]
  end
  traders<<kite_connect
end
File.open('config/login.yaml', 'w') {|f| f.write CLIENTS.to_yaml }

kite_ticker = KiteTicker.new(traders.first.access_token,traders.first.api_key,APP)

feeder1 = Feeder.new(kite_ticker,DATA,260105)
feeder2 = Feeder.new(kite_ticker,DATA,260105)

strategy1 = StrategyHighLow.new(traders, feeder,LOG1)
feeder1.start
