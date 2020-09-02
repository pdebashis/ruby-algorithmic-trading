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
    @result=""
    
    @candle1=[]
    @candle2=[]

    @target=0
    @stop_loss=0
    @tolerence=limit
    @net_day=0
  end

  def start
    @feeder.start
  end
  
  def on_tick tick
    @logger.info tick
  end
  
  def on_bar bar
    bar.bar_data.each do |symbol, data|
      @logger.info "received #{data}"
      time = date[:time]
      opening = data[:open]
      high = data[:high]
      low = data[:low]
      closing = data[:close]

      levels=get_levels(closing) if levels.empty?

      assign_candle1 if @candle1.empty?
    end
  end

  private 

  def reset_counters
    @levels=[]
    @candle1=[]
    @candle2=[]
  end

  def get_levels(closing_value)
    raise "Targets not enclosing the data points" if targets.first > closing_value or targets.last < closing_value 
    @level_config.levels.each_with_index { |t,n|
      return [targets[n-1],t] if t > closing_value
    }
  end

  def assign_candle1(o,h,l,c)
    if l <= @levels[0] and h >= @levels[1]
      @logger.info "UNDECIDED due to high and low outside levels"
      reset_counters
    end

    if h >= levels[1]
      candle1=[c,h,l,o,"RED1"]
      @logger.info "RED1"
    end

    if l <= levels[0]
      candle1=[closing,high,low,opening,"GREEN1"]
      @logger.info "GREEN1"
    end

    levels=[]
    @logger.info "UNDECIDED due to high and low inside levels"
  end
end