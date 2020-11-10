require_relative '../bar'
require_relative 'bigcandle'
require 'frappuccino'
require 'logger'
require 'yaml'
require 'faye/websocket'
require 'eventmachine'

class Feeder

  def initialize 
    
    data_file_path="2020.csv"
    targets_file_path="./../../config/levels.yaml"

    raise "Source file not found" unless File.file? data_file_path
    raise "Levels file not found" unless File.file? targets_file_path

    result_filepath=File.dirname(data_file_path)
    result_filename="result_" + File.basename(data_file_path)

    @data_in_file=""
    @today=""    

    @new_date=""
    @old_date=""
    @target=0
    @stop_loss=0
    @tolerence=0
    @net_day=0

    File.open(data_file_path, "r") do |fp|
      while !fp.eof? do @data_in_file << fp.gets end
    end

    @ticks = {}      
    @bars = {}
  end

  def start
    EventMachine.run do
    @data_in_file.lines.each do |line|

      opening,high,low,closing,timestamp=line.split(",")

      closing=closing.to_i
      high=high.to_i
      low=low.to_i
      opening=opening.to_i
      p timestamp
      new_date=timestamp.split("T")[0]
      new_time=timestamp.split("T")[1][0..4]

      if timestamp.include? ("09:15") or @today != new_date
        @today=new_date
      end 

      emit tick: opening
      emit tick: high
      emit tick: low
      emit tick: closing

      d = {
        date: @today,
        time: new_time,
        open: opening,
        high: high,
        low: low,
        close: closing,
      }
      add_bar d
    end
    end
  end

  def add_bar hash
    time = hash[:time]
    @bars[time] ||= Bar.new @today
    @bars[time].add_bar_data @instrument,hash
    emit bar: @bars[time]
  end

end

LOG=Logger.new('results/bigcandle_backtest.log', 'daily', 30)

a=Feeder.new 
StrategyBigCandle.new(a, LOG)
a.start



