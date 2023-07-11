module RubyAMI
  class Connection
    include Celluloid::IO

    delegate :readpartial, to: :socket
    delegate :write, to: :socket
    delegate :close, to: :socket

    def initialize(host:, port:, username:, password:, write_only: false)
      self.socket = TCPSocket.from_ruby_socket ::TCPSocket.new(host, port)
      self.username = username
      self.password = password
      if write_only
        login("Off")
      else
        login
      end
    end

    def dispatch_action(*args, &block)
      action = Action.new *args, &block
      logger.trace "[SEND] #{action.to_s}"
      socket.write(action.to_s)
      action
    end

  private

    attr_accessor :socket, :username, :password

    def login(event_mask = "On")
      dispatch_action "Login",
        "Username" => username,
        "Secret" => password,
        "Events" => event_mask
    end
  end
end
