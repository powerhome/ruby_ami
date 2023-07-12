# encoding: utf-8

require "connection_pool"

module RubyAMI
  class Stream
    class ConnectionStatus
      def name
        self.class.to_s
      end

      def eql?(other)
        other.is_a? self.class
      end

      alias :== :eql?
    end

    Connected = Class.new ConnectionStatus
    Disconnected = Class.new ConnectionStatus

    include Celluloid::IO

    attr_reader :logger

    finalizer :finalize

    def initialize(host, port, username, password, event_callback, logger = Logger, timeout = 0)
      super()
      @host, @port, @username, @password, @event_callback, @logger, @timeout = host, port, username, password, event_callback, logger, timeout
      logger.debug "Starting up..."
      @lexer = Lexer.new self
      @sent_actions   = {}
      @causal_actions = {}
    end

    [:started, :stopped, :ready].each do |state|
      define_method("#{state}?") { @state == state }
    end

    def run
      @read_socket = Connection.new(host: @host, port: @port, username: @username, password: @password)
      send_action("Login", "Username" => @username, "Secret" => @password, "Events" => "On")
      @write_socket_pool = ConnectionPool.new(size: 10, timeout: @timeout) do
        Connection.new(host: @host, port: @port, username: @username, password: @password, write_only: true)
        send_action("Login", "Username" => @username, "Secret" => @password, "Events" => "Off")
      end

      post_init
      loop { receive_data @read_socket.readpartial(4096) }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      logger.error "Connection failed due to #{e.class}. Check your config and the server."
    rescue EOFError
      logger.info "Client socket closed!"
    rescue Timeout::Error
      logger.error "Timeout exceeded while trying to connect."
    ensure
      async.terminate
    end

    def post_init
      @state = :started
      fire_event Connected.new
    end

    def send_data(data)
      @write_socket_pool.with { |sock| sock.write data }
    end

    def send_action(name, headers = {}, error_handler = self.method(:abort))
      condition = Celluloid::Condition.new
      action = @write_socket_pool.with do |sock|
        sock.dispatch_action name, headers do |response|
          condition.signal response
        end
      end
      logger.warn "[ACTION] #{action.inspect}"
      register_sent_action action
      condition.wait
      action.response.tap do |resp|
        if resp.is_a? Exception
          error_handler.call(resp)
        end
      end
    end

    def receive_data(data)
      logger.trace "[RECV] #{data}"
      @lexer << data
    end

    def message_received(message)
      logger.trace "[RECV] #{message.inspect}"
      case message
      when Event
        action = causal_action_for_event message
        if action
          action << message
          complete_causal_action_for_event message if action.complete?
        else
          fire_event message
        end
      when Response, Error
        action = sent_action_for_response message
        raise StandardError, "Received an AMI response with an unrecognized ActionID! #{message.inspect}" unless action
        action << message
      end
    end

    def syntax_error_encountered(ignored_chunk)
      logger.error "Encountered a syntax error. Ignoring chunk: #{ignored_chunk.inspect}"
    end

    alias :error_received :message_received

    private

    def fire_event(event)
      @event_callback.call event
    end

    def register_sent_action(action)
      @sent_actions[action.action_id] = action
      register_causal_action action if action.has_causal_events?
    end

    def sent_action_with_id(action_id)
      @sent_actions.delete action_id
    end

    def sent_action_for_response(response)
      sent_action_with_id response.action_id
    end

    def register_causal_action(action)
      @causal_actions[action.action_id] = action
    end

    def causal_action_for_event(event)
      @causal_actions[event.action_id]
    end

    def complete_causal_action_for_event(event)
      @causal_actions.delete event.action_id
    end

    def finalize
      logger.debug "Finalizing stream"
      @read_socket.close if @read_socket
      @write_socket_pool.shutdown { |sock| sock.close }
      @state = :stopped
      fire_event Disconnected.new
    end
  end
end
