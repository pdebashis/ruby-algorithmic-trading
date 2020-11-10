require 'net/https'
require 'uri'
require 'json'

class ExtractCandles
  attr_reader :url

  def initialize()
    @from_date="2020-07-02"
    @to_date="2020-09-01"
    @user="NC7756"
    @authorizaton="enctoken 9PVOxnmGDAbNxwRmImrJpmSXyYuZoZ12bJ/Wm215Jiv1goMKLbTMoL0J9yNiu/9u6x4s92m9eMyjgdy9KoGC3chrgaFtHg=="
  end

  def any?
  	parsed_json = JSON.parse(response_body)
  	parsed_json["data"]["candles"].each do |child|

      puts "#{child[1]},#{child[2]},#{child[3]},#{child[4]},#{child[0]}"
  	end
  	""
  end

  private

  def response_body
  	uri = URI("https://kite.zerodha.com/oms/instruments/historical/260105/15minute?user_id=#{@user}&oi=1&from=#{@from_date}&to=#{@to_date}")

	response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
	  request = Net::HTTP::Get.new(uri)
	  request["authorization"] = @authorizaton
	  http.request(request) 
	end

    response.body
  end


end

puts ExtractCandles.new().any?
