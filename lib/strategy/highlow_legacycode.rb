class StrategyHighLow
  def initialize traders, feeder, logger=nil
    @user = traders.first[:kite_api]
    @users = traders
    @feeder = feeder
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:bar) && !event[:bar].nil? }.
      map{ |event| event[:bar] }.
      on_value(&method(:on_bar))

    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:tick) && !event[:tick].nil? }.
      map{ |event| event[:tick] }.
      on_value(&method(:on_tick))
   
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:strike) && !event[:strike].nil? }.
      map{ |event| event[:strike] }.
      on_value(&method(:on_strike))

    @telegram_bot=TelegramBot.new

    @logger = logger
    @quantity=0
    @levels=[]
    @candle=[]

    @target=0
    @stop_loss=0
    @tolerence=0

    @net_day=0
    @net_bnf=0
   
    @index = @feeder.instrument.to_s
    @instrument = 0
    @strike = ""
    @trade_target = 99999
    @trade_exit = -99999
    @day_target = 99999
    @trade_flag=false
  end

  def book_pl_strike strike
    profit= strike - @candle[2]
    if profit > @trade_target or profit < @trade_exit
      sell_position
      @net_bnf+=profit
      telegram "TRADE CAP REACHED(#{profit}), SELLING POSITION NET_BNF:#{@net_bnf}"
      reset_counters
    end
  end

  def on_strike strike 
    unless @candle.empty?
      book_pl_strike(strike) if @candle[4].eql? "BUY" or @candle[4].eql? "SELL"
    end
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
        telegram "MARKET CLOSED :: NET:#{@net_day};NET_BNF:#{@net_bnf}"
      else
        @levels=get_levels(closing) if @levels.empty?
        assign_candle(opening,high,low,closing) if @candle.empty?
      end
    end
  end

  private 

  def telegram msg
    @logger.info msg
    #@telegram_bot.send_message "[highlow] #{msg}" 
  end

  def buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_ce].to_s
    @strike = config[@index][:strike_ce]
    @quantity = config[@index][:quantity]
    @trade_target = config.target_per_trade.to_i
    @trade_exit = config.exit_per_trade.to_i 
    @day_target = config.target_per_day.to_i 
   
    if @trade_flag 
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end

    @feeder.subscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp.values.first["last_price"] unless ltp.values.empty?
  end

  def buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_pe].to_s
    @strike = config[@index][:strike_pe]
    @quantity = config[@index][:quantity]
    @trade_target = config.target_per_trade.to_i
    @trade_exit = config.exit_per_trade.to_i
    @day_target = config.target_per_day.to_i  
    
    if @trade_flag
      @users.each do |usr|
       kite_usr=usr[:kite_api]
       kite_usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty? 
      end
    end
 
    @feeder.subscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp.values.first["last_price"] unless ltp.values.empty?
  end

  def sell_position
    
    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        kite_usr.place_cnc_order(@strike, "SELL", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end
    
    @feeder.unsubscribe(@instrument)
    ltp = @user.ltp(@instrument)
    @instument = 0
    @strike = ""
    ltp.values.first["last_price"] unless ltp.values.empty? 
  end

  def reset_counters
    @levels=[]
    @candle=[]
    if @net_bnf > @day_target and @trade_flag
      @logger.info "DAY TARGET ACHIEVED(#{@day_target})"
      @trade_flag=false
    end
  end

  def get_levels(closing_value)
    level_config=OpenStruct.new YAML.load_file('config/levels.yaml') 
    targets = level_config.levels.sort
    raise "Targets not enclosing the data points" if targets.first > closing_value or targets.last < closing_value 
    targets.each_with_index { |t,n|
      return [targets[n-1],t] if t > closing_value
    }
  end

  def assign_candle(o,h,l,c)
    if l <= @levels[0] and h >= @levels[1]
      telegram "UNDECIDED due to high and low outside levels"
      reset_counters
    elsif h >= @levels[1]
      @candle=[c,h,l,o,"RED"]
      telegram "RED"
    elsif l <= @levels[0]
      @candle=[c,h,l,o,"GREEN"]
      telegram "GREEN"
    else
      reset_counters
      telegram "UNDECIDED due to high and low inside levels"
    end
  end

  def do_action(tick)
    if @candle[4] == "GREEN"
      if tick > @levels[0]
        @levels=get_levels(tick)
        @target=@levels[1]
        @stop_loss=@levels[0]
        ltp = buy_ce
        @candle=[0,0,ltp,tick,"BUY"]
        telegram "ORDER PLACED #{@strike} for quantity #{@quantity} at #{ltp}"
        @logger.info "BUY Banknifty@ #{tick}; target:#{@target};SL:#{@stop_loss}"
      else
        telegram "NO ACTION due to market lower than level"
        reset_counters
      end
    end

    if @candle[4] == "RED"
      if tick < @levels[1]
        @levels=get_levels(tick)
        @target=@levels[0]
        @stop_loss=@levels[1]
        ltp=buy_pe
        @candle=[0,0,ltp,tick,"SELL"]
        telegram "ORDER PLACED #{@strike} for quantity #{@quantity} at #{ltp}"
        @logger.info "SELL Banknifty@ #{tick}; target:#{@target};SL:#{@stop_loss}"
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
            ltp=sell_position
            diffe2 = ltp-@candle[2]
            @net_bnf+=diffe2
            telegram "STOPLOSS HIT:#{diffe};#{@strike}:#{ltp};BNF_POINTS:#{diffe2}"
            @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
            reset_counters
          elsif tick < @target
            diffe=@candle[3]-tick
            @net_day+=diffe
            ltp=sell_position
            diffe2= ltp-@candle[2]
            @net_bnf+=diffe2
            telegram "TARGET HIT:#{diffe};#{@strike}:#{ltp};BNF_POINTS:#{diffe2}"
            @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
            reset_counters
          end
    end

    if @candle[4] == "BUY"
        if tick > @target
          diffe = tick - @candle[3]
          @net_day+=diffe
          ltp=sell_position
          diffe2 = ltp - @candle[2]
          @net_bnf+=diffe2
          telegram "TARGET HIT:#{diffe};strike:#{ltp};BNF_POINTS:#{diffe2}"
          @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
          reset_counters
        elsif tick < @stop_loss
          diffe= tick - @candle[3]
          @net_day+=diffe
          ltp=sell_position
          diffe2 = ltp - @candle[2]
          @net_bnf+=diffe2
          telegram "STOPLOSS HIT:#{diffe};strike:#{ltp};BNF_POINTS:#{diffe2}"
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
      ltp=sell_position
      diffe2 = ltp - @candle[2]
      telegram "END TRADE:#{differen};strike:#{ltp};BNF_POINTS:#{diffe2}"
    elsif @candle[4] == "BUY"
      differen = close - @candle[3]
      ltp=sell_position
      diffe2 = ltp - @candle[2]
      telegram "END TRADE:#{differen};strike:#{ltp};BNF_POINTS:#{diffe2}"
    end
    @net_day+=differen
    @net_bnf+=diffe2
    @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
    reset_counters
  end
end
