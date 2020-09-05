require 'uri'
require 'digest'
require 'csv'
require 'rest-client'
require 'json'
require 'faye/websocket'
require 'eventmachine'

class KiteTicker
  EXCHANGE_MAP = {
        nse: 1,
        nfo: 2,
        cds: 3,
        bse: 4,
        bfo: 5,
        bsecds: 6,
        mcx: 7,
        mcxsx: 8,
        indices: 9
  }

  ROOT_URI = "wss://ws.kite.trade"

  MODES = ["full","quote","ltp"]

  attr_accessor :socket_url, :logger, :feeder, :ws

  def initialize(access_token, api_key, logger=nil)
    self.socket_url = ROOT_URI + "?access_token=#{access_token}&api_key=#{api_key}"
    self.logger = logger
    self.ws = nil
  end
  
  def subscribe (token)
    begin
      d = {a: "subscribe", v: [token.to_i]}
      @ws.send(d.to_json.to_s)
    rescue
      return false
    end
  end

  def set_mode (mode,token)
    return false unless MODES.include? mode

    begin
      d = {a: "mode", v: [mode,[token.to_i]]}
      @ws.send(d.to_json.to_s)
    rescue
      return false
    end
  end

  def make_sense(bin)
    parse_binary_custom(bin)
  end

  private

    def parse_binary_custom(bin)
        packets = split_packets(bin)
        data = []

        packets.each do |packet|
            instrument_token = unpack_int(packet, 0, 4)
            segment = instrument_token & 0xff

            divisor = 100.0
            divisor = 10000000.0 if segment == EXCHANGE_MAP[:cds]

            # LTP packets
            if packet.size == 8
                data << {
                    last_price: unpack_int(packet, 4, 8) / divisor
                }
            elsif packet.size == 28 or packet.size == 32
                d = {
                    last_price: unpack_int(packet, 4, 8) / divisor,
                }

                # Full mode with timestamp
                if packet.size == 32
                    begin
                        timestamp = unpack_int(packet, 28, 32)
                        daytime=Time.at(timestamp)
                    rescue
                        daytime = nil
                    end
                  d[:timestamp] = daytime
                end
                

                data << d
            # Quote and full mode
            elsif packet.size == 44 or packet.size == 184

                d = {
                    instrument_token: instrument_token,
                    last_price: unpack_int(packet, 4, 8) / divisor,
                    last_quantity: unpack_int(packet, 8, 12),
                    average_price: unpack_int(packet, 12, 16) / divisor,
                    volume: unpack_int(packet, 16, 20),
                    buy_quantity: unpack_int(packet, 20, 24),
                    sell_quantity: unpack_int(packet, 24, 28),
                    ohlc: {
                        open: unpack_int(packet, 28, 32) / divisor,
                        high: unpack_int(packet, 32, 36) / divisor,
                        low: unpack_int(packet, 36, 40) / divisor,
                        close: unpack_int(packet, 40, 44) / divisor
                    }
                }

                # Compute the change price using close price and last price
                d[:change] = 0
                if d[:ohlc][:close] != 0
                    d[:change] = (d[:last_price] - d[:ohlc][:close]) * 100 / d[:ohlc][:close]
                end
              end

                # Parse full mode
              if packet.size == 184
                    begin
                        last_trade_time = unpack_int(packet, 44, 48)
                        daytime=Time.at(last_trade_time)
                    rescue
                        daytime = nil
                    end

                    begin
                        timestamp = unpack_int(packet, 60, 64)
                        daytime=Time.at(timestamp)
                    rescue
                        daytime = nil
                    end

                    d[:last_trade_time] = last_trade_time
                    d[:oi] = unpack_int(packet, 48, 52)
                    d[:oi_day_high] = unpack_int(packet, 52, 56)
                    d[:oi_day_low] = unpack_int(packet, 56, 60)
                    d[:timestamp] = daytime

                    # Market depth entries.
                    depth = {
                        buy: [],
                        sell: []
                    }

                    # Compile the market depth lists.
                    (64..packet.size).step(12).each_with_index do |i,p|
                        e = {
                            quantity: unpack_int(packet, p, p + 4),
                            price: unpack_int(packet, p + 4, p + 8) / divisor,
                            orders: unpack_int(packet, p + 8, p + 10, 'n*')
                        }
                        if i >= 5
                          depth[:sell] << e 
                        else
                          depth[:buy] << e
                        end

                    d[:depth] = depth
                    end
                  data.append(d)
                end
          end
        data
     end

  def parse_binary(bin)
        packets = split_packets(bin)
        data = []

        packets.each do |packet|
            instrument_token = unpack_int(packet, 0, 4)
            segment = instrument_token & 0xff

            divisor = 100.0
            divisor = 10000000.0 if segment == EXCHANGE_MAP[:cds]

            tradable = true
            tradable = false if segment == EXCHANGE_MAP[:indices]

            # LTP packets
            if packet.size == 8
                data << {
                    tradable: tradable,
                    mode: MODE_LTP,
                    instrument_token: instrument_token,
                    last_price: unpack_int(packet, 4, 8) / divisor
                }
            elsif packet.size == 28 or packet.size == 32
                mode = MODE_FULL
                mode = MODE_QUOTE if packet.size == 28

                d = {
                    tradable: tradable,
                    mode: mode,
                    instrument_token: instrument_token,
                    last_price: unpack_int(packet, 4, 8) / divisor,
                    ohlc: {
                        high: unpack_int(packet, 8, 12) / divisor,
                        low: unpack_int(packet, 12, 16) / divisor,
                        open: unpack_int(packet, 16, 20) / divisor,
                        close: unpack_int(packet, 20, 24) / divisor
                    }
                }

                # Compute the change price using close price and last price
                d[:change] = 0
                if(d[:ohlc][:close] != 0)
                    d[:change] = (d[:last_price] - d[:ohlc][:close]) * 100 / d[:ohlc][:close]
                end

                # Full mode with timestamp
                if packet.size == 32
                    begin
                        timestamp = unpack_int(packet, 28, 32)
                        daytime=Time.at(timestamp)
                    rescue
                        daytime = nil
                    end
                  d["timestamp"] = daytime
                end
                

                data << d
            # Quote and full mode
            elsif packet.size == 44 or packet.size == 184
                mde = MODE_FULL
                mode = MODE_QUOTE if packet.size == 44

                d = {
                    tradable: tradable,
                    mode: mode,
                    instrument_token: instrument_token,
                    last_price: unpack_int(packet, 4, 8) / divisor,
                    last_quantity: unpack_int(packet, 8, 12),
                    average_price: unpack_int(packet, 12, 16) / divisor,
                    volume: unpack_int(packet, 16, 20),
                    buy_quantity: unpack_int(packet, 20, 24),
                    sell_quantity: unpack_int(packet, 24, 28),
                    ohlc: {
                        open: unpack_int(packet, 28, 32) / divisor,
                        high: unpack_int(packet, 32, 36) / divisor,
                        low: unpack_int(packet, 36, 40) / divisor,
                        close: unpack_int(packet, 40, 44) / divisor
                    }
                }

                # Compute the change price using close price and last price
                d[:change] = 0
                if d[:ohlc][:close] != 0
                    d[:change] = (d[:last_price] - d[:ohlc][:close]) * 100 / d[:ohlc][:close]
                end
              end

                # Parse full mode
              if packet.size == 184
                    begin
                        last_trade_time = unpack_int(packet, 44, 48)
                        daytime=Time.at(last_trade_time)
                    rescue
                        daytime = nil
                    end

                    begin
                        timestamp = unpack_int(packet, 60, 64)
                        daytime=Time.at(timestamp)
                    rescue
                        daytime = nil
                    end

                    d[:last_trade_time] = last_trade_time
                    d[:oi] = unpack_int(packet, 48, 52)
                    d[:oi_day_high] = unpack_int(packet, 52, 56)
                    d[:oi_day_low] = unpack_int(packet, 56, 60)
                    d[:timestamp] = daytime

                    # Market depth entries.
                    depth = {
                        buy: [],
                        sell: []
                    }

                    # Compile the market depth lists.
                    (64..packet.size).step(12).each_with_index do |i,p|
                        e = {
                            quantity: unpack_int(packet, p, p + 4),
                            price: unpack_int(packet, p + 4, p + 8) / divisor,
                            orders: unpack_int(packet, p + 8, p + 10, 'n*')
                        }
                        if i >= 5
                          depth[:sell] << e 
                        else
                          depth[:buy] << e
                        end

                    d[:depth] = depth
                    end
                  data.append(d)
                end
          end
        data
     end

    def split_packets(bin)
        # Ignore heartbeat data.
        return [] if bin.size < 2

        number_of_packets = unpack_int(bin, 0, 2,'n*')
        packets = []

        j = 2
        number_of_packets.times do |i|
          packet_length = unpack_int(bin, j, j + 2,'n*')
          packets << bin[j+2...j+2+packet_length]
          j = j + 2 + packet_length
        end
        packets
    end

    def unpack_int(bin, start, finis,byte_format='N*')

#C    | Integer | 8-bit unsigned (unsigned char)
#n    | Integer | 16-bit unsigned, network (big-endian) byte order
#N    | Integer | 32-bit unsigned, network (big-endian) byte order

      bin_bin=bin.pack('C*')
      bin_bin[start...finis].unpack(byte_format).join.to_i
    end

end