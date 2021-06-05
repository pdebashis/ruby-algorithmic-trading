class StrategyLevelBreakout
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
    @quantity=25
    @net_day=0
    @net_year=0
    @trade_flag=false
    @instrument = "FAKE INSTRUMENT" 
    @strike = "FAKE STRIKE"
    @trade_target = 100
    @trade_exit = -50
    @day_target = 300

    @levels = []
    @candle_body_min_size=40
    @candle_shadow_max_size=50
    @candle_max_dist_from_lev=30
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
        @logger.info "MARKET CLOSED"
      elsif time.eql? "15:15" or time.eql? "15:30" or time.eql? "15:45"
        @logger.info "----"
      else
        @levels=get_levels(closing)
        print "#{time} matches basic conditions" if matches_basic_conditions(opening,high,low,closing)
      end
    end
  end

  def get_levels(closing_value)
    level_config=OpenStruct.new YAML.load_file('./../../config/levels.yaml') 
    targets = level_config.levels.sort
    raise "Targets not enclosing the data points" if targets.first > closing_value or targets.last < closing_value 
    targets.each_with_index { |t,n|
      return [targets[n-1],t] if t > closing_value
    }
  end

  def matches_basic_conditions(o,h,l,c)
    return false if h < @levels[1] and l > @levels[0]
    candle_body_size=(o-c).abs
    candle_color = o < c ? "GREEN" : "RED"
    shodow_size = c - l if candle_color == "RED"
    shodow_size = h - o if candle_color == "GREEN"
    dist_from_lev = c - @levels[0] if candle_color == "GREEN"
    dist_from_lev = @levels[1] - c if candle_color == "RED"
    return true if candle_body_size > @candle_body_min_size and shodow_size < @candle_shadow_max_size and dist_from_lev < @candle_max_dist_from_lev
  end

  def on_tick tick
  #   if @orb_decision_map[:wait_buy]
  #     if tick > @orb_decision_map[:high]
  #       @orb_decision_map[:trigger]=@orb_decision_map[:high]
  #       @orb_decision_map[:target]=@orb_decision_map[:trigger]+300
  #       @orb_decision_map[:buy]=true
  #       @orb_decision_map[:stoploss]=@orb_decision_map[:trigger]-80
  #       orb_buy_ce
  #     end
  #     if tick < @orb_decision_map[:low]
  #       @orb_decision_map[:trigger]=@orb_decision_map[:low]
  #       @orb_decision_map[:target]=@orb_decision_map[:trigger]-300
  #       @orb_decision_map[:buy]=false
  #       @orb_decision_map[:stoploss]=@orb_decision_map[:trigger]+80
  #       orb_buy_pe
  #     end
  #   end
   

  #   if @decision_map[:wait_buy] && !@orb_decision_map[:wait_sell]
  #     if @decision_map[:green]
  #       buy_ce if tick > @decision_map[:trigger_price] && @decision_map[:size] < 100 
  #     else
  #       buy_pe if tick < @decision_map[:trigger_price] && @decision_map[:size] < 100
  #     end 
  #   end

  #   if @orb_decision_map[:wait_sell]
  #     if @orb_decision_map[:buy]
  #       orb_sell_pos @orb_decision_map[:target] if tick >= @orb_decision_map[:target]
  #       orb_sell_pos @orb_decision_map[:stoploss] if tick <= @orb_decision_map[:stoploss]
  #     end

  #     if ! @orb_decision_map[:buy]
  #       orb_sell_pos @orb_decision_map[:target] if tick <= @orb_decision_map[:target]
  #       orb_sell_pos @orb_decision_map[:stoploss] if tick >= @orb_decision_map[:stoploss] 
  #     end 
  #   end


  #   if @decision_map[:wait_sell]
  #     if @decision_map[:green]
  #       #target_value = @decision_map[:trigger_price] + (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
	#  sell_position @decision_map[:target_value] if tick > @decision_map[:target_value]
  #        sell_position @decision_map[:stop_loss] if tick < @decision_map[:stop_loss]
  #     else
  #       #target_value = @decision_map[:trigger_price] - (@decision_map[:big_candle_high]-@decision_map[:big_candle_low])
  #       sell_position @decision_map[:target_value] if tick < @decision_map[:target_value]
  #       sell_position @decision_map[:stop_loss] if tick > @decision_map[:stop_loss]
  #     end
  #   end
  end

  private

  def check_orb(high,low,time)
    return unless time.eql? "09:15"
      
    orb_size=(low-high).abs
    if orb_size <= 150 && orb_size >= 50 
       @logger.info "ORB candle formed #{orb_size}"
       @orb_decision_map[:high]=high
       @orb_decision_map[:low]=low
       @orb_decision_map[:wait_buy]=true
    else
       @orb_decision_map[:wait_buy]=false
       @logger.info "ORB candle notformed #{orb_size}"
    end
  end

  def reset_counters
    # @decision_map[:big_candle]=false
    # @decision_map[:wait_buy]= false
    # @decision_map[:wait_sell]=false
    # @decision_map[:green] = nil 
    # @decision_map[:stop_loss]=nil
    # @decision_map[:trigger_price] = nil
    # @decision_map[:ltp_at_buy]=nil
    # @decision_map[:big_candle_high]=0
    # @decision_map[:big_candle_low]=0
    # @decision_map[:size]=0
  end

  def is_big_candle?(o,h,l,c)
    return true if (h-l).abs > 60 && (o-c).abs > 40
  end

  def check_big_candle(o,h,l,c)
    @decision_map[:big_candle] = false
    return if @decision_map[:wait_sell]
    return unless is_big_candle?(o,h,l,c)
    reset_counters
    @decision_map[:size]=(h-l).abs
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
      if @decision_map[:size] > 100
        @decision_map[:stop_loss]= @decision_map[:green] ? l : h
      end
      @decision_map[:wait_buy]=true
      @logger.info "DECISION MAP : #{@decision_map}"
    else
      @logger.info "BREAKOUT OF RANGE"
    
      if @decision_map[:wait_buy] 
      if @decision_map[:green]
        buy_ce if c > @decision_map[:trigger_price] && @decision_map[:size] > 100 
        return if c > @decision_map[:trigger_price] && @decision_map[:size] > 100
      else
        buy_pe if c < @decision_map[:trigger_price] && @decision_map[:size] > 100
        return if c < @decision_map[:trigger_price] && @decision_map[:size] > 100
      end
      end
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

  def orb_buy_ce
    @logger.info "ORBBUY CE ORDER PLACED at #{@orb_decision_map[:trigger]}; TARGET: #{@orb_decision_map[:target]} ; SL: #{@orb_decision_map[:stoploss]}"
    @orb_decision_map[:wait_buy]=false
    @orb_decision_map[:wait_sell]=true
  end

  def orb_buy_pe

    @logger.info "ORBBUY PE ORDER PLACED at #{@orb_decision_map[:trigger]}; TARGET: #{@orb_decision_map[:target]} ; SL: #{@orb_decision_map[:stoploss]}"
    @orb_decision_map[:wait_buy]=false
    @orb_decision_map[:wait_sell]=true
  end

  def orb_sell_pos tick
    @orb_decision_map[:wait_sell]=false
  
    if @orb_decision_map[:buy]
      difference = tick - @orb_decision_map[:trigger]
    else
      difference = @orb_decision_map[:trigger] - tick
    end

    @net_day+=difference 

    @logger.info "ORBSELL SOLD at #{tick} difference #{difference}"
  

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

    @logger.info "NORMAL SOLD at #{tick} difference #{difference}"
    @instument = 0
    @strike = ""
  end

  def close_day close
    # @logger.info "MARKET CLOSE REACHED POINTS:#{@net_day}" unless @decision_map[:wait_sell]
    # return unless @decision_map[:wait_sell] or  @orb_decision_map[:wait_sell]
    # sell_position close if @decision_map[:wait_sell]
    # orb_sell_pos close if @orb_decision_map[:wait_sell]
    # @logger.info "MARKET CLOSE REACHED by END TRADE POINTS:#{@net_day}"
  end
end


