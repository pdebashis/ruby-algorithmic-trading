################################
#Telegram API can be tested by calling below :
#https://api.telegram.org/bot<token>/sendMessage?chat_id=@channelname&text=hi
################################

require 'telegram/bot'
require 'yaml'

class TelegramBot
  def initialize
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @token = config.telegram_bot 
    @chat_id= config.chat_id
  end

  def send_message msg
    Telegram::Bot::Client.run(@token) do |bot|
      bot.api.send_message(chat_id: @chat_id, text: msg)
    end
  end
end
