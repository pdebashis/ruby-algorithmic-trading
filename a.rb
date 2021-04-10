require_relative 'lib/fyer/fyer_connect'
require_relative 'lib/telegram/bot'
require 'frappuccino'
require 'logger'
require 'yaml'

traders=[]

CLIENTS=YAML.load_file 'config/fyer.yaml'
CLIENTS.each do |client|
  fyer_connect = FyerConnect.new(client[:api_key],APP)

  unless client[:access_token].nil?
    kite_connect.set_access_token(client[:access_token])
    APP.info "Using ACCESS TOKEN From Database"
  else
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
  traders<< {kite_api: kite_connect, lot_size_nifty: client[:lot_size_nifty], lot_size_banknifty: client[:lot_size_banknifty] , client_id: client[:client], last_login: client[:login_time]}
end
File.open('config/login.yaml', 'w') {|f| f.write CLIENTS.to_yaml }

ticker_user = traders.first[:kite_api]
kite_ticker = KiteTicker.new(ticker_user.access_token,ticker_user.api_key,APP)

telegram_bot=TelegramBot.new
intro_msg="GLHF\n"
traders.each do |trader|
  intro_msg += "ID:#{trader[:client_id]}:Lotsize BNF:#{trader[:lot_size_banknifty]} NF:#{trader[:lot_size_nifty]}\n"

end
