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
    @decision_map

    @levels = []
    @candle_body_min_perc=0.07
    @candle_shadow_max_perc=0.25
    @candle_max_dist_from_lev=0.10
    @decision_map={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :green => nil, :target_value => 0}
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
        if matches_basic_conditions(opening,high,low,closing) and @decision_map[:wait_sell] != true
          print "#{time} matches basic conditions"
          @decision_map[:trigger_price] = closing
          @decision_map[:stop_loss] = @decision_map[:green] ? low : high
          place_order
        end
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
    @decision_map[:green] =  candle_color == "GREEN" ? true : false
    shodow_size = c - l if candle_color == "RED"
    shodow_size = h - c if candle_color == "GREEN"
    dist_from_lev = c - @levels[0] if candle_color == "GREEN"
    dist_from_lev = @levels[1] - c if candle_color == "RED"

    body_shadow_ratio = candle_body_size*2.5 > shodow_size
    levels_diff = @levels[1] - @levels[0]
    return false unless body_shadow_ratio

    candle_body_size_matches = candle_body_size > @candle_body_min_perc * levels_diff
    candle_shadow_size_matches = shodow_size < @candle_shadow_max_perc * levels_diff
    candle_dist_from_level_matches = dist_from_lev < @candle_max_dist_from_lev * levels_diff
    @logger.info("BODY:#{candle_body_size} SHADOW:#{shodow_size} DISTFROMLVL:#{dist_from_lev} LEVELSIZE:#{levels_diff}")
    return true if candle_body_size_matches and candle_shadow_size_matches and candle_dist_from_level_matches
  end

  def place_order
    if @decision_map[:green]
      buy_ce
    else
      buy_pe
    end
  end

  def on_tick tick

    if @decision_map[:wait_sell]
      if @decision_map[:green]
        sell_position @decision_map[:target_value] if tick > @decision_map[:target_value]
        sell_position @decision_map[:stop_loss] if tick < @decision_map[:stop_loss]
      else
        sell_position @decision_map[:target_value] if tick < @decision_map[:target_value]
        sell_position @decision_map[:stop_loss] if tick > @decision_map[:stop_loss]
      end
    end
  end

  private

  def reset_counters
    @decision_map[:wait_buy]= false
    @decision_map[:wait_sell]=false
    @decision_map[:green] = nil 
    # @decision_map[:stop_loss]=nil
    @decision_map[:trigger_price] = nil
    # @decision_map[:ltp_at_buy]=nil
    # @decision_map[:big_candle_high]=0
    # @decision_map[:big_candle_low]=0
    # @decision_map[:size]=0
  end

  def buy_ce 
    target_value = [@levels[1],@decision_map[:trigger_price] + 150].min
    stop_loss = [@decision_map[:stop_loss], @decision_map[:trigger_price]-50].max
    @decision_map[:stop_loss] = stop_loss
    @decision_map[:target_value] = target_value

    @logger.info "ORDER PLACED CE at #{@decision_map[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map[:stop_loss]}"
    @logger.info "#{@decision_map}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
  end

  def buy_pe 
    target_value = [@levels[0],@decision_map[:trigger_price] - 150].max
    stop_loss = [@decision_map[:stop_loss], @decision_map[:trigger_price]+50].min
    @decision_map[:stop_loss] = stop_loss
    @decision_map[:target_value] = target_value

    @logger.info "ORDER PLACED PE at #{@decision_map[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map[:stop_loss]}"
    @logger.info "#{@decision_map}"
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
    @logger.info "MARKET CLOSE REACHED POINTS:#{@net_day}" unless @decision_map[:wait_sell]
    return unless @decision_map[:wait_sell]
    sell_position close if @decision_map[:wait_sell]
    @decision_map[:wait_sell] = false
    @logger.info "MARKET CLOSE REACHED by END TRADE POINTS:#{@net_day}"
  end
end


