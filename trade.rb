require_relative 'lib/kite/kite_connect'
require_relative 'lib/fyer/fyer_connect'
require_relative 'lib/kite/kite_ticker'
require_relative 'lib/feeder'
require_relative 'lib/bar'
require_relative 'lib/strategy/bigcandle'
require_relative 'lib/strategy/levelbreakout_green'
require_relative 'lib/strategy/levelbreakout_red'
require_relative 'lib/telegram/bot'
require 'frappuccino'
require 'logger'
require 'yaml'

APP=Logger.new('logs/app.log')
DATA=Logger.new('logs/data.log')
LOG1=Logger.new('logs/bigcandle_banknifty.log', 'weekly', 30)
LOG2=Logger.new('logs/bigcandle_nifty.log', 'weekly', 30)
LOG3=Logger.new('logs/levelbreakout_banknifty.log', 'weekly', 30)

APP.formatter = proc do |severity, datetime, _progname, msg|
  date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
  "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

DATA.formatter = proc do |severity, datetime, _progname, msg|
  date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")  
  "[#{date_format}] #{msg}\n"
end

log_formatter = proc do |severity, datetime, _progname, msg|
    date_format = datetime.getlocal("+05:30").strftime("%Y-%m-%d %H:%M:%S")
    "[#{date_format}] #{severity.ljust(5)}: #{msg}\n"
end

LOG1.formatter = log_formatter 
LOG2.formatter = log_formatter
LOG3.formatter = log_formatter

traders=[]
traders_fyer=[]
traders_all=[]

CLIENTS=YAML.load_file 'config/login.yaml'
CLIENTS.each do |client|
  kite_connect = KiteConnect.new(client[:api_key],APP)

  unless client[:access_token].nil?
    kite_connect.set_access_token(client[:access_token])
    APP.info "Using ACCESS TOKEN From Database"
  else
    next if client[:request_token].nil?
    begin
      login_details=kite_connect.generate_access_token(client[:request_token], client[:api_secret])
    rescue
      puts "login failed = #{login_details}"
      APP.info "login failed = #{login_details}"
      next
    end
    APP.info "Updating ACCESS TOKEN in Database"
    client[:access_token] = kite_connect.access_token
    client[:login_time] = login_details["login_time"]
  end
  funds=kite_connect.margins["equity"]["available"]["live_balance"]
  traders<< {kite_api: kite_connect, lot_size_nifty: client[:lot_size_nifty], lot_size_banknifty: client[:lot_size_banknifty] , client_id: client[:client], last_login: client[:login_time], funds: funds, level_break_enable: client[:level_break_enable]}
end
File.open('config/login.yaml', 'w') {|f| f.write CLIENTS.to_yaml }

ticker_user = traders.first[:kite_api]
kite_ticker = KiteTicker.new(ticker_user.access_token,ticker_user.api_key,APP)

telegram_bot=TelegramBot.new
intro_msg="GLHF\n"
intro_msg +="---KITE Users\n"
traders.each do |trader|
  intro_msg += "ID:#{trader[:client_id]}:Lotsize BNF:#{trader[:lot_size_banknifty]} NF:#{trader[:lot_size_nifty]} FUNDS:#{trader[:funds]}\n" 
end

CLIENTS_FYER=YAML.load_file 'config/fyer.yaml'
CLIENTS_FYER.each do |client|
  fyer_connect = FyerConnect.new(client[:api_key],APP)
  unless client[:access_token].nil?
    fyer_connect.set_access_token(client[:access_token])
    APP.info "Using ACCESS TOKEN From Database"
  else
    next if client[:request_token].nil?
    begin
      login_details=fyer_connect.generate_access_token(client[:request_token], client[:api_secret])
    rescue
      puts "login failed = #{login_details}"
      APP.info "login failed = #{login_details}"
      next
    end
    APP.info "Updating ACCESS TOKEN in Database"
    client[:access_token] = fyer_connect.access_token
    client[:login_time] = Time.now.getlocal("+05:30")
  end
  margins = fyer_connect.margins["fund_limit"] 
  funds = margins ? margins.select{ |x| x["id"] == 10 }[0]["equityAmount"] : 0
  traders_fyer << {kite_api: ticker_user, fyer_api: fyer_connect, lot_size_nifty: client[:lot_size_nifty], lot_size_banknifty: client[:lot_size_banknifty] , client_id: client[:client], last_login: client[:login_time], funds: funds,level_break_enable: client[:level_break_enable]}
end
File.open('config/fyer.yaml', 'w') {|f| f.write CLIENTS_FYER.to_yaml }
intro_msg +="---FYER Users\n"
traders_fyer.each do |trader|
  intro_msg += "ID:#{trader[:client_id]}:Lotsize BNF:#{trader[:lot_size_banknifty]} NF:#{trader[:lot_size_nifty]} FUNDS:#{trader[:funds]}\n"
end

APP.info intro_msg
telegram_bot.send_message intro_msg

feeder1 = Feeder.new(kite_ticker,DATA,260105)
feeder2 = Feeder.new(kite_ticker,DATA,256265)
feeder3 = Feeder.new(kite_ticker,DATA,260105)
feeder4 = Feeder.new(kite_ticker,DATA,260105)

traders_all = traders_all.concat traders
traders_all = traders_all.concat traders_fyer

StrategyBigCandle.new(traders_all, feeder1, LOG1)
StrategyBigCandle.new(traders_all, feeder2, LOG2)
StrategyLevelBreakoutGreen.new(traders_all, feeder3, LOG3)
StrategyLevelBreakoutRed.new(traders_all, feeder4, LOG3)

fork do
  APP.info "Running Bigcandle strategy"
  feeder1.start  
  exit
end

fork do
  APP.info "Running BigCandle strategy"
  feeder2.start
  exit
end

fork do
  APP.info "Running LevelBreakout GREEN strategy"
  feeder3.start
  exit
end

fork do
  APP.info "Running LevelBreakout RED strategy"
  feeder4.start
  exit
end

Process.waitall
