require 'frappuccino'
require 'logger'
require 'yaml'

class Feeder

  def initialize 
    
    @data_file_path="2020.csv"
    @targets_file_path="./../../config/levels.yaml"

    raise "Source file not found" unless File.file? data_file_path
    raise "Levels file not found" unless File.file? targets_file_path

    result_filepath=File.dirname(data_file_path)
    result_filename="result_" + File.basename(data_file_path)

    @data_in_file=""
    @targets=[]
    @result=""
    @levels=[]

    @new_date=""
    @old_date=""
    @target=0
    @stop_loss=0
    @tolerence=0
    @net_day=0

    File.open(@data_file_path, "r") do |fp|
      while !fp.eof? do @data_in_file << fp.gets end
    end

    @ticks = {}      
    @bars = {}
  end

  def start
    
  end

  def fetch tick
    @logger.info tick
    tick.each do |hash_of_tick|
      unless hash_of_tick[:instrument_token].equal? @instrument
        fetch_strike_tick hash_of_tick 
        next
      end 
      epoch = hash_of_tick[:timestamp]
      
      time_now=Time.at(epoch).getlocal("+05:30")
      
      close_ws if time_now > @d2 
      return unless time_now.between?(@d1,@d2)

      time_h = time_now.hour
      time_m = time_now.min
      time_c = time_m/15
      time = "#{time_h}:#{time_c*15}"
      last_price = hash_of_tick[:last_price]
 
      if @ticks[time]
        emit tick: last_price
        @ticks[time] << last_price
      else
        persist_bar unless @ticks.empty?
        @ticks = {}
        @ticks[time] = [last_price]
        @logger.info "signal:new time frame received"
        emit tick: last_price
      end
    end
  end

  private

  def persist_bar
    @logger.debug "Number of ticks captured in last time frame:#{@ticks.values.first.size}"
    return if @ticks.values.first.size < 600
    @ticks.each do |k,v|
      d = {
        time: k,
        open: v.first,
        high: v.max,
        low: v.min,
        close: v.last,
      }
      add_bar d
    end
  end

  def add_bar hash
    time = hash[:time]
    @bars[time] ||= Bar.new @today
    @bars[time].add_bar_data @instrument,hash
    @logger.info "Emitted Bar"
    emit bar: @bars[time]
  end

  def fetch_strike_tick hash
    emit strike: hash[:last_price]
  end


  def close_ws
    @logger.info "signal:close received"
    @logger.info @bars
    @ticker.ws.close
  end
end

