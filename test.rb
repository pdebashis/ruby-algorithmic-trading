require_relative 'kite_connect'
require_relative 'kite_ticker'
require_relative 'feeder'
require_relative 'bar'
require_relative 'strategy_highlow'
require 'frappuccino'
require 'logger'
require 'yaml'

CONFIG = OpenStruct.new YAML.load_file 'config/config.yaml'

today=Time.now.strftime("%H:%M:%S")
LOG=Logger.new('logs/app.log', 'daily', 30)

LOG.info "STARTED Thread for #{Time.now}"

kite_connect = KiteConnect.new(CONFIG.api_key,LOG)

unless CONFIG.access_token.nil?
  kite_connect.set_access_token(CONFIG.access_token)
  LOG.info "Using ACCESS TOKEN From Database"
else
  LOG.info kite_connect.generate_access_token(CONFIG.request_token, CONFIG.api_secret)
  LOG.info "Updating ACCESS TOKEN in Database"
  CONFIG[:access_token] = kite_connect.access_token
  File.open('config/config.yaml', 'w') {|f| f.write CONFIG.to_yaml }
end

kite_ticker = KiteTicker.new(kite_connect.access_token,kite_connect.api_key,LOG)
feeder = Feeder.new(kite_ticker,LOG)

strategy = StrategyHighLow.new(feeder, LOG)

strategy.start


#kite_connect.place_cnc_order("BANKNIFTY2090324400CE", "BUY", 25, nil, "MARKET")
#kite_connect.place_cnc_order("BANKNIFTY2090324400CE", "SELL", 25, nil, "MARKET")
#kite_connect.place_cnc_order("BANKNIFTY2090324400PE", "BUY", 25, nil, "MARKET")
#kite_connect.place_cnc_order("BANKNIFTY2090324400PE", "SELL", 25, nil, "MARKET")