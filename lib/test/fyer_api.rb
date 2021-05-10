
load './lib/fyer/fyer_connect.rb'
require_relative 'lib/kite/kite_ticker'
require_relative 'lib/feeder'
require_relative 'lib/bar'
require_relative 'lib/strategy/bigcandle'
require_relative 'lib/strategy/bigcandleclosing'
require_relative 'lib/telegram/bot'
require 'frappuccino'
require 'logger'
require 'yaml'

APP=Logger.new('logs/app.log')
CLIENTS_FYER=YAML.load_file 'config/fyer.yaml'
client = CLIENTS_FYER.first
fyer_connect = FyerConnect.new(client[:api_key],APP)
 fyer_connect.set_access_token(client[:access_token]) or  fyer_connect.generate_access_token(client[:request_token], client[:api_secret])
fyer_connect.profile

