require_relative 'lib/kite/kite_connect'
require_relative 'lib/kite/kite_ticker'
require_relative 'lib/feeder'
require_relative 'lib/bar'
require_relative 'lib/strategy/highlow'
require_relative 'lib/strategy/bigcandle'
require_relative 'lib/strategy/bigcandleclosing'
require_relative 'lib/telegram/bot'
require 'frappuccino'
require 'logger'
require 'yaml'

APP=Logger.new('logs/app.log')
DATA=Logger.new('logs/data.log')
LOG1=Logger.new('logs/strategy_highlow.log', 'weekly', 30)
LOG2=Logger.new('logs/strategy_bigcandle.log', 'weekly', 30)
LOG3=Logger.new('logs/strategy_bigcandle_closing.log', 'weekly', 30)
LOG4=Logger.new('logs/strategy_bigcandle2.log', 'weekly', 30)

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
LOG3.formatter = log_formatter
LOG4.formatter = log_formatter

traders=[]

CLIENTS=YAML.load_file 'config/login.yaml'
CLIENTS.each do |client|
  kite_connect = KiteConnect.new(client[:api_key],APP)

  unless client[:access_token].nil?
    kite_connect.set_access_token(client[:access_token])
    APP.info "Using ACCESS TOKEN From Database"
  else
    begin
      login_details=kite_connect.generate_access_token(client[:request_token], client[:api_secret])
    rescue
      next
    end
    APP.info "Updating ACCESS TOKEN in Database"
    client[:access_token] = kite_connect.access_token
    client[:login_time] = login_details["login_time"]
  end
  traders<< {kite_api: kite_connect, lot_size: client[:lot_size], client_id: client[:client], last_login: client[:login_time]}
end
File.open('config/login.yaml', 'w') {|f| f.write CLIENTS.to_yaml }

ticker_user = traders.first[:kite_api]
kite_ticker = KiteTicker.new(ticker_user.access_token,ticker_user.api_key,APP)

telegram_bot=TelegramBot.new
intro_msg="GLHF\n"
traders.each do |trader|
  intro_msg += "ID:#{trader[:client_id]}:Lotsize:#{trader[:lot_size]}\n" 
  APP.info intro_msg
end
telegram_bot.send_message intro_msg

feeder1 = Feeder.new(kite_ticker,DATA,260105)
feeder2 = Feeder.new(kite_ticker,DATA,260105)
feeder3 = Feeder.new(kite_ticker,DATA,260105)
feeder4 = Feeder.new(kite_ticker,DATA,256265)

StrategyHighLow.new(traders, feeder1, LOG1)
StrategyBigCandle.new(traders, feeder2, LOG2)
StrategyBigCandleClosing.new(traders, feeder3, LOG3)
StrategyBigCandle.new(traders, feeder4, LOG4)

highlow_pid = fork do
  puts "Running HighLow strategy"
  feeder1.start  
  exit
end

puts "The PID of the highlow process is #{highlow_pid}"

bigcandle_pid = fork do
  puts "Running BigCandle strategy"
  feeder2.start
  exit
end

puts "The PID of the bigcandle process is #{bigcandle_pid}"

bigcandle_closing_pid = fork do
  puts "Running BigCandle Closing strategy"
  feeder3.start
  exit
end

puts "The PID of the bigcandle process is #{bigcandle_closing_pid}"

bigcandle2_closing_pid = fork do
  puts "Running BigCandle Closing strategy"
  feeder4.start
  exit
end

puts "The PID of the bigcandle2 process is #{bigcandle2_closing_pid}"

Process.waitall
