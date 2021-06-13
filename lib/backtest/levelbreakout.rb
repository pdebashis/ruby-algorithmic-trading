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
    @candle_color = nil
    @candle_body_min_perc=0.07
    @candle_shadow_max_perc=0.25
    @candle_max_dist_from_lev=0.10
    @decision_map_green={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0}
    @decision_map_red={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0}
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
        @net_year+=@net_day
        @net_day=0
        p @net_year
      elsif time.eql? "15:00"
        @logger.info "MARKET CLOSED"
      elsif time.eql? "15:15" or time.eql? "15:30" or time.eql? "15:45"
        @logger.info "----"
      else
        @levels=get_levels(closing)
        if matches_basic_conditions(opening,high,low,closing)
          print "#{time} matches basic conditions"
          if @candle_color == "GREEN"
            @decision_map_green[:trigger_price] = closing
            @decision_map_green[:stop_loss] = low
            place_order
          else
            @decision_map_red[:trigger_price] = closing
            @decision_map_red[:stop_loss] = high
            place_order
          end
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
    @candle_color = o < c ? "GREEN" : "RED"
    levels_diff = @levels[1] - @levels[0]

    shodow_size =  @candle_color == "RED" ? c - l : h - c
    dist_from_lev =  @candle_color == "GREEN" ? c - @levels[0] : @levels[1] - c
    body_shadow_ratio = candle_body_size*2.5 > shodow_size
    @logger.info("BODY:#{candle_body_size} SHADOW:#{shodow_size} DISTFROMLVL:#{dist_from_lev} LEVELSIZE:#{levels_diff} COLOR:#{@candle_color}")
    return false unless body_shadow_ratio

    candle_body_size_matches = candle_body_size > @candle_body_min_perc * levels_diff
    candle_shadow_size_matches = shodow_size < @candle_shadow_max_perc * levels_diff
    candle_dist_from_level_matches = dist_from_lev < @candle_max_dist_from_lev * levels_diff
    dist_not_zero = dist_from_lev > 0
    shadow_not_zero = shodow_size > 0
    not_zero = dist_not_zero and shadow_not_zero
    @logger.info("BODY:#{candle_body_size_matches} SHADOW:#{candle_shadow_size_matches} DISTFROMLVL:#{candle_dist_from_level_matches} NOTZERO:#{not_zero}")
    return true if candle_body_size_matches and candle_shadow_size_matches and candle_dist_from_level_matches and not_zero
  end

  def place_order
    if @candle_color == "GREEN"
      buy_ce
    else
      buy_pe
    end
  end

  def on_tick tick
    if @decision_map_green[:wait_sell]
      sell_position(@decision_map_green[:target_value],"GREEN") if tick > @decision_map_green[:target_value]
      sell_position(@decision_map_green[:stop_loss],"GREEN") if tick < @decision_map_green[:stop_loss]
    end
  
    if @decision_map_red[:wait_sell]
      sell_position(@decision_map_red[:target_value],"RED") if tick < @decision_map_red[:target_value]
      sell_position(@decision_map_red[:stop_loss],"RED") if tick > @decision_map_red[:stop_loss]
    end
  end

  private

  def reset_counters(color=nil)

    if color == "GREEN"
      @decision_map_green[:wait_buy]= false
      @decision_map_green[:wait_sell]=false
      @decision_map_green[:green] = nil 
      @decision_map_green[:stop_loss]=nil
      @decision_map_green[:trigger_price] = nil
    elsif color == "RED"
      @decision_map_red[:wait_buy]= false
      @decision_map_red[:wait_sell]=false
      @decision_map_red[:green] = nil 
      @decision_map_red[:stop_loss]=nil
      @decision_map_red[:trigger_price] = nil
    else
      @decision_map_red[:wait_buy]= false
      @decision_map_red[:wait_sell]=false
      @decision_map_red[:green] = nil 
      @decision_map_red[:stop_loss]=nil
      @decision_map_red[:trigger_price] = nil
      @decision_map_green[:wait_buy]= false
      @decision_map_green[:wait_sell]=false
      @decision_map_green[:green] = nil 
      @decision_map_green[:stop_loss]=nil
      @decision_map_green[:trigger_price] = nil
    end
  end

  def buy_ce 
    target_value = [@levels[1],@decision_map_green[:trigger_price] + 250].min
    #stop_loss = [@decision_map_green[:stop_loss], @decision_map_green[:trigger_price]-50].max
    stop_loss=@decision_map_green[:stop_loss]
    @decision_map_green[:stop_loss] = stop_loss
    @decision_map_green[:target_value] = target_value

    @logger.info "ORDER PLACED CE at #{@decision_map_green[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map_green[:stop_loss]}"
    @logger.info "#{@decision_map_green}"
    @decision_map_green[:wait_buy]=false
    @decision_map_green[:wait_sell]=true
  end

  def buy_pe 
    target_value = [@levels[0],@decision_map_red[:trigger_price] - 250].max
    #stop_loss = [@decision_map_red[:stop_loss], @decision_map_red[:trigger_price]+50].min
    stop_loss=@decision_map_red[:stop_loss]
    @decision_map_red[:stop_loss] = stop_loss
    @decision_map_red[:target_value] = target_value

    @logger.info "ORDER PLACED PE at #{@decision_map_red[:trigger_price]}; TARGET: #{target_value} ; SL: #{@decision_map_red[:stop_loss]}"
    @logger.info "#{@decision_map_red}"
    @decision_map_red[:wait_buy]=false
    @decision_map_red[:wait_sell]=true
  end

  def sell_position(tick,color) 
    if color == "GREEN"
      @decision_map_green[:wait_sell]=false
      difference = tick - @decision_map_green[:trigger_price]
    else
      @decision_map_red[:wait_sell]=false
      difference = @decision_map_red[:trigger_price] - tick
    end 
     
    @net_day+=difference

    @logger.info "NORMAL SOLD at #{tick} difference #{difference}"
    @instument = 0
    @strike = ""
  end

  def close_day close
    @logger.info "MARKET CLOSE REACHED POINTS:#{@net_day}" unless @decision_map_green[:wait_sell] or @decision_map_red[:wait_sell]
    return unless @decision_map_green[:wait_sell] or @decision_map_red[:wait_sell]
    sell_position(close,"GREEN") if @decision_map_green[:wait_sell]
    sell_position(close,"RED") if @decision_map_red[:wait_sell]
    reset_counters
    @logger.info "MARKET CLOSE REACHED by END TRADE POINTS:#{@net_day}"
  end
end