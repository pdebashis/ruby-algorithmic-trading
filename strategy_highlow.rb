######################### The high high and low low strategy
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

    #Is candle1 red?
    # Is current closing below previous level 1
      # Is current low touching current level 0?
        #Yes -> this is new candle 1 and it is green
        #No -> this is consecutive red candle (sell for target -z)
    # Is current closing above previous level 1
      # If Current high touching current level 1
      #reset levels
        # Yes -> this is red2 (sell for target -z)
        # No -> this is new candle 1 and it is green
##########################

class StrategyHighLow
  def initialize feeder, logger=nil, starting_capital=0, commission_per_trade=0, limit=0
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

    @level_config=OpenStruct.new YAML.load_file('config/levels.yaml')
    @levels=[]

    @candle=[]

    @target=0
    @stop_loss=0
    @tolerence=0
    @net_day=0
  end

  def start
    @feeder.start
  end
  
  def on_tick tick
    do_action(tick) if @candle[4].eql? "GREEN" or @candle[4].eql? "RED"
    book_pl(tick) if @candle[4].eql? "CALL" or @candle[4].eql? "PUT"  
  end
  
  def on_bar bar
    @logger.info bar
    bar.bar_data.each do |symbol, data|
      @logger.info "received #{data}"
      time = data[:time]
      opening = data[:open]
      high = data[:high]
      low = data[:low]
      closing = data[:close]

      if time.eql? "15:00"
        close_day(c)
      elsif time.eql? "15.15"
       @logger.info "NET:#{@netday}"
      end
      @levels=get_levels(closing) if @levels.empty?
      assign_candle(opening,high,low,closing) if @candle.empty?
    end
  end

  private 

  def reset_counters
    @levels=[]
    @candle=[]
  end

  def get_levels(closing_value)
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
    elsif h >= @levels[1]
      @candle=[c,h,l,o,"RED"]
      @logger.info "RED"
    elsif l <= @levels[0]
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
        @target=@levels[1]
        @target=[tick+tolerence,levels[1]].min if @tolerence>0

        @stop_loss=@levels[0]
        @stop_loss=[tick-@tolerence,@levels[0]].max if @tolerence>0
        @candle[4]="CALL"
        @candle[3]=tick
        @logger.info "BUY CALL near #{tick}; target:#{@target};SL:#{@stop_loss}"
      else
        @logger.info "NO ACTION due to market lower than level"
        reset_counters
      end
    end

    if @candle[4] == "RED"
      if tick < @levels[1]
        @levels=get_levels(tick)
        @target=@levels[0]
        @target=[tick-@tolerence,@levels[0]].max if @tolerence>0

        @stop_loss=@levels[1]
        @stop_loss=[tick+@tolerence,@levels[1]].min if @tolerence>0
        @candle[4]="PUT"
        @candle[3]=tick
        @logger.info "BUY PUT near #{tick}; target:#{@target};SL:#{@stop_loss}"
      else
        @logger.info "NO ACTION due to market higher than level"
        reset_counters
      end
    end
  end

  def book_pl tick
    if @candle[4] == "PUT"
          if tick > @stop_loss
            diffe = tick - @candle[3]
            @net_day+=diffe
            @logger.info "LOSS:#{diffe}"
            reset_counters
          elsif tick < @target
            diffe=tick-@candle[3]
            @net_day+=diffe
            @logger.info "PROFIT:#{diffe}"
            reset_counters
          end
    end

    if @candle[4] == "CALL"
      if tick > @target
        diffe = tick - @candle[3]
        @net_day+=diffe
        @logger.info "PROFIT:#{diffe}"
        reset_counters
      elsif tick < @stop_loss
        diffe=tick-@candle[3]
        @net_day+=diffe
        @logger.info "LOSS:#{diffe}"
        reset_counters
      end
    end
  end

  def close_day close
    differen=0
    if @candle[4] == "PUT"
      differen = @candle[3] - close
      @logger.info "END TRADE:#{differen}"
    elsif @candle[4] == "CALL"
      differen = close - @candle[3]
      @logger.info "END TRADE #{differen}"
    end
    net_day+=differen
  end
end