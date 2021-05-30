load './lib/kite/kite_connect.rb'
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
CLIENTS_KITE=YAML.load_file 'config/kite.yaml'
client = CLIENTS_KITE.first
kite_connect = FyerConnect.new(client[:api_key],APP)
 kite_connect.set_access_token(client[:access_token]) or  fyer_connect.generate_access_token(client[:request_token], client[:api_secret])
kite_connect.profile