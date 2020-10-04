######################### The Big Candle strategy
    #Is candle1 green?
    # Is current closing above previous level 0 
      # Is current high touching current level 1?
        #Yes -> this is new candle 1 and it is red
        #No -> this is consecutive green candle (buy for target z)
    # Is current closing below previous level 0
      # If Current low touching current level 0
      #reset levels
        # Yes -> this is green2 (buy for target -z)
        # No -> this is new candle 1 and it is red

##########################

##########################

#kite_connect.place_cnc_order(@sell_instrument, "BUY", 25, nil, "MARKET")
#kite_connect.place_cnc_order(@sell_instrument, "SELL", 25, nil, "MARKET")
#kite_connect.place_cnc_order(@buy_instrument, "BUY", 25, nil, "MARKET")
#kite_connect.place_cnc_order(@buy_instrument, "SELL", 25, nil, "MARKET")

##########################

class StrategyEliminateSL
  def initialize kite_connect, feeder, logger=nil
    @user = kite_connect
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:bar) && !event[:bar].nil? }.
      map{ |event| event[:bar] }.
      on_value(&method(:on_bar))

    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:tick) && !event[:tick].nil? }.
      map{ |event| event[:tick] }.
      on_value(&method(:on_tick))
    @logger = logger

    @level_config=OpenStruct.new YAML.load_file('config/levels.yaml')
    @levels=[]
    @candle=[]

    @target=0
    @stop_loss=0

    @net_day=0
    @net_bnf=0
    
    @buy_instrument = 0
    @sell_instrument = 0
  end

  def on_tick tick
    unless @candle.empty?
      do_action(tick) if @candle[4].eql? "GREEN" or @candle[4].eql? "RED"
      book_pl(tick) if @candle[4].eql? "BUY" or @candle[4].eql? "SELL"  
    end
  end
  
  def on_bar bar
    bar.bar_data.each do |symbol, data|
      @logger.info "NEW CANDLE #{data}"
      time = data[:time]
      opening = data[:open]
      high = data[:high]
      low = data[:low]
      closing = data[:close]

      if time.eql? "14:45"
        close_day(closing)
      elsif time.eql? "15:0"
        @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
      elsif time.eql? "9:0"
        @logger.info "GLHF"
      else
        @levels=get_levels(closing) if @levels.empty?
        assign_candle(opening,high,low,closing) if @candle.empty?
      end
    end
  end

  private 

  def ltp_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @buy_instrument = config.instrument_ce.to_s
    @user.ltp(@buy_instrument).values.first["last_price"]
  end

  def ltp_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @sell_instrument = config.instrument_pe.to_s
    @user.ltp(@sell_instrument).values.first["last_price"]
  end

  def reset_counters
    @levels=[]
    @candle=[]
  end

  def get_levels(closing_value)
    @level_config=OpenStruct.new YAML.load_file('config/levels.yaml') 
    targets = @level_config.levels.sort
    raise "Targets not enclosing the data points" if targets.first > closing_value or targets.last < closing_value 
    targets.each_with_index { |t,n|
      return [targets[n-1],t] if t > closing_value
    }
  end

  def assign_candle(o,h,l,c)
    if l <= @levels[0] and h >= @levels[1]
      @logger.info "UNDECIDED due to high and low outside levels"
      reset_counters
    elsif h >= @levels[1] and c < @levels[1]-10
      @candle=[c,h,l,o,"RED"]
      @logger.info "RED"
    elsif l <= @levels[0] and c > @levels[0]+10
      @candle=[c,h,l,o,"GREEN"]
      @logger.info "GREEN"
    else
      reset_counters
      @logger.info "UNDECIDED due to high and low inside levels"
    end
  end

  def do_action(tick)
    if @candle[4] == "GREEN"
      if tick > @levels[0]
        @levels=get_levels(tick)
        @target= @levels[1] 

        @stop_loss=@levels[0]
        ltp = ltp_ce
        @candle=[0,0,ltp,tick,"BUY"]
        @logger.info "BUY Banknifty@ #{tick}; target:#{@target};SL:#{@stop_loss};LTP:#{ltp}"
      else
        @logger.info "NO ACTION due to market lower than level"
        reset_counters
      end
    end

    if @candle[4] == "RED"
      if tick < @levels[1]
        @levels=get_levels(tick)
        @target=@levels[0]

        @stop_loss=@levels[1]
        ltp=ltp_pe
        @candle=[0,0,ltp,tick,"SELL"]
        @logger.info "SELL Banknifty@ #{tick}; target:#{@target};SL:#{@stop_loss};LTP:#{ltp}"
      else
        @logger.info "NO ACTION due to market higher than level"
        reset_counters
      end
    end
  end

  def book_pl tick
    if @candle[4] == "SELL"
          if tick > @stop_loss
            diffe = @candle[3]-tick
            @net_day+=diffe
            ltp=ltp_pe
            diffe2 = ltp-@candle[2]
            @net_bnf+=diffe2
            @logger.info "STOPLOSS HIT:#{diffe};LTP:#{ltp};BNF_POINTS:#{diffe2}"
            @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
            reset_counters
          elsif tick < @target
            diffe=@candle[3]-tick
            @net_day+=diffe
            ltp=ltp_pe
            diffe2= ltp-@candle[2]
            @net_bnf+=diffe2
            @logger.info "TARGET HIT:#{diffe};LTP:#{ltp};BNF_POINTS:#{diffe2}"
            @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
            reset_counters
          end
    end

    if @candle[4] == "BUY"
      if tick > @target
        diffe = tick - @candle[3]
        @net_day+=diffe
        ltp=ltp_ce
        diffe2 = ltp - @candle[2]
        @net_bnf+=diffe2
        @logger.info "TARGET HIT:#{diffe};LTP:#{ltp};BNF_POINTS:#{diffe2}"
        @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
        reset_counters
      elsif tick < @stop_loss
        diffe= tick - @candle[3]
        @net_day+=diffe
        ltp=ltp_ce
        diffe2 = ltp - @candle[2]
        @net_bnf+=diffe2
        @logger.info "STOPLOSS HIT:#{diffe};LTP:#{ltp};BNF_POINTS:#{diffe2}"
        @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
        reset_counters
      end
    end
  end

  def close_day close
    differen=0
    diffe2=0
    if @candle[4] == "SELL"
      differen = @candle[3] - close
      ltp=ltp_pe
      diffe2 = ltp - @candle[2]
      @logger.info "END TRADE:#{differen};LTP:#{ltp};BNF_POINTS:#{diffe2}"
    elsif @candle[4] == "BUY"
      differen = close - @candle[3]
      ltp=ltp_ce
      diffe2 = ltp - @candle[2]
      @logger.info "END TRADE if holding:#{differen};LTP:#{ltp};BNF_POINTS:#{diffe2}"
    end
    @net_day+=differen
    @net_bnf+=diffe2
    @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
  end
end
