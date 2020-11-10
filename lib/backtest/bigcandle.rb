class StrategyBigCandle
  def initialize feeder, logger=nil
    @feeder = feeder
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:bar) && !event[:bar].nil? }.
      map{ |event| event[:bar] }.
      on_value(&method(:on_bar))

    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:tick) && !event[:tick].nil? }.
      map{ |event| event[:tick] }.
      on_value(&method(:on_tick))
   
    @logger = logger
    @quantity=0
    @levels=[]
    @decision_map={:big_candle => false, :trigger_price => 0, :wait_buy => false, :wait_sell => false}

    @net_day=0
    @net_year=0
   
    @instrument = 0
    @strike = ""
    @trade_flag=true

    @instrument = "FAKE INSTRUMENT" 
    @strike = "FAKE STRIKE"
    @quantity = 25
    @trade_target = 100
    @trade_exit = -50
    @day_target = 300

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
        reset_counters
        @net_year+=@net_day
        @net_day=0
        p @net_year
      elsif time.eql? "15:00"
        @logger.info "MARKET CLOSED :: NET:#{@net_day}"
      elsif time.eql? "15:15" or time.eql? "15:30" or time.eql? "15:45"
        @logger.info "----"
      else
        return if @decision_map[:wait_sell]
        check_inside_candle(opening,high,low,closing) if @decision_map[:big_candle]
        check_big_candle(opening,high,low,closing) unless @decision_map[:big_candle]
      end
    end
  end

  def on_tick tick
    if @decision_map[:wait_buy]
      if @decision_map[:green]
        buy_ce if tick > @decision_map[:trigger_price]  
      else
        buy_pe if tick < @decision_map[:trigger_price]
      end 
    end

    if @decision_map[:wait_sell]
      if @decision_map[:green]
        #target_value = @decision_map[:trigger_price] + (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
	 sell_position @decision_map[:target_value] if tick > @decision_map[:target_value]
         sell_position @decision_map[:stop_loss] if tick < @decision_map[:stop_loss]
      else
        #target_value = @decision_map[:trigger_price] - (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
        sell_position @decision_map[:target_value] if tick < @decision_map[:target_value]
        sell_position @decision_map[:stop_loss] if tick > @decision_map[:stop_loss]
      end
    end
  end

  private

  def reset_counters
    @decision_map[:big_candle]=false
    @decision_map[:wait_buy]= false
    @decision_map[:wait_sell]=false
    @decision_map[:green] = nil 
    @decision_map[:stop_loss]=nil
    @decision_map[:trigger_price] = nil
    @decision_map[:ltp_at_buy]=nil
    @decision_map[:big_candle_high]=0
    @decision_map[:big_candle_low]=0
  end

  def is_big_candle?(o,h,l,c)
    return true if (o-c).abs > 50
  end

  def check_big_candle(o,h,l,c)
    @decision_map[:big_candle] = false
    return if @decision_map[:wait_sell]
    return unless is_big_candle?(o,h,l,c)
    reset_counters
    @decision_map[:big_candle]=true
    @decision_map[:green] = o < c ? true : false
    if @decision_map[:green]
      @logger.info "BIG GREEN CANDLE FORMED"
    else
      @logger.info "BIG RED CANDLE FORMED"
    end
    @decision_map[:trigger_price] = @decision_map[:green] ? h : l
    @decision_map[:stop_loss]= @decision_map[:green] ? l : h
    @decision_map[:big_candle_high]=h
    @decision_map[:big_candle_low]=l
  end

  def check_inside_candle(o,h,l,c)
    if h < @decision_map[:big_candle_high] and l > @decision_map[:big_candle_low]
      @logger.info "INSIDE CANDLE FORMED"
      @decision_map[:wait_buy]=true
      @logger.info "DECISION MAP : #{@decision_map}"
    else
      @logger.info "BREAKOUT OF RANGE"
      reset_counters
      check_big_candle(o,h,l,c)
    end
  end

  def buy_ce 
    @decision_map[:ltp_at_buy]=@decision_map[:trigger_price]
    #target_value = @decision_map[:trigger_price] + (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
    target_value = @decision_map[:trigger_price] + 150    
    @decision_map[:target_value] = target_value

    @logger.info "ORDER PLACED at #{@decision_map[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map[:stop_loss]}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
  end

  def buy_pe 
    @decision_map[:ltp_at_buy]=@decision_map[:trigger_price]
    #target_value = @decision_map[:trigger_price] - (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
    target_value = @decision_map[:trigger_price] - 150  
    @decision_map[:target_value] = target_value
 
    @logger.info "ORDER PLACED at #{@decision_map[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map[:stop_loss]}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
  end

  def sell_position tick 
    @decision_map[:wait_sell]=false
    if @decision_map[:green]
      difference = tick - @decision_map[:trigger_price]
    else
      difference = @decision_map[:trigger_price] - tick
    end 
     
    @net_day+=difference

    @logger.info "SOLD at #{tick} difference #{difference}"
    @instument = 0
    @strike = ""
  end

  def close_day close
    @logger.info "MARKET CLOSE REACHED POINTS:#{@net_day}" unless @decision_map[:wait_sell]
    return unless @decision_map[:wait_sell]
    sell_position close
    @logger.info "MARKET CLOSE REACHED by END TRADE POINTS:#{@net_day}"
  end
end


