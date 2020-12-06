require 'net/https'
require 'uri'
require 'json'

class ExtractCandles
  attr_reader :url

  def initialize()
    @from_date="2019-01-01"
    @to_date="2019-03-31"
    @user="NC7756"
    @authorizaton="enctoken 1XcpULyrjA5RQiPiHcpjLQ4YXyaG6RYdss3JEvxO8dZ8punQC8CEmLQ5LjWo29jFZVWViA4dE+d970/J1QirNsKhiCWDvw=="
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
