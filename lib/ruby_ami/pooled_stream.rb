require "connection_pool"

module RubyAMI
  class PooledStream
    def initialize(options)
      self.options = options
    end

    def run
      stream = RubyAMI::Stream.new(*option_stream_values)
      create_writer_pool
      create_readers
      stream.run
    end

    def method_missing(method, *args, &block)
      writer_stream_pool.with do |stream|
        stream.__send__(method, *args, &block)
      end
    end

    private
    attr_accessor :options, :writer_stream_pool, :reader_stream

    def create_writer_pool
      self.writer_stream_pool = ConnectionPool.new(size: 10, timeout: 5) do
        stream = RubyAMI::Stream.new(*option_stream_values, 'Off')
        stream.async.run
        stream
      end
    end

    def create_readers
      event_types = [
        'TestEvent', 
        'Newchannel', 
        'VarSet', 
        'Newexten', 
        'NewCallerid', 
        'NewConnectedLine', 
        'DialBegin', 
        'Newstate', 
        'OriginateResponse', 
        'DialEnd', 
        'AsyncAGIStart', 
        'DeviceStateChange', 
        'AGIExecStart', 
        'AGIExecEnd', 
        'AsyncAGIExec', 
        'MixMonitorStart', 
        'BridgeCreate', 
        'BridgeEnter', 
        'MusicOnHoldStart', 
        'BridgeLeave', 
        'BridgeDestroy', 
        'AsyncAGIEnd', 
        'SoftHangupRequest', 
        'Hangup', 
        'MusicOnHoldStop'
      ]
      event_types.each do |event_type|
        stream = RubyAMI::Stream.new(*option_stream_values)
        stream.async.run
        sleep 1 #it fails if event gets sent too soon
        stream.send_action 'Filter', 'Filter' => "Event: #{event_type}", 'Operation' => 'Add'
      end
      reader_stream = RubyAMI::Stream.new(*option_stream_values)
      reader_stream.async.run
      sleep 1
      event_types.each do |event_type|
        reader_stream.send_action 'Filter', 'Filter' => "!Event: #{event_type}", 'Operation' => 'Add'
      end
    end

    def option_stream_values
      options.values_at(
        :host, 
        :port, 
        :username, 
        :password, 
        :event_callback, 
        :logger, 
        :timeout
      )
    end
  end
end