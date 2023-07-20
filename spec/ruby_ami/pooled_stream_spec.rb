# encoding: utf-8
require 'spec_helper'

module RubyAMI
  describe PooledStream do
    it 'should call send_action on stream in pool' do
      pooled_stream = pooled_stream_with_options
      stream = double(run: nil, async: double(run: nil), send_action: nil)
      allow(RubyAMI::Stream).to receive(:new).and_return(stream)
      pooled_stream.run
      12.times.each { pooled_stream.send_action }
      expect(stream).to have_received(:send_action).exactly(12).times
    end

    it 'should call run on stream' do
      pooled_stream = pooled_stream_with_options
      stream = double(run: nil, async: double(run: nil), send_action: nil)
      allow(RubyAMI::Stream).to receive(:new).and_return(stream)
      pooled_stream.run
      expect(stream).to have_received(:run).exactly(1).times
      expect(stream).to have_received(:async).at_least(1).times
    end
  end

  def pooled_stream_with_options
    described_class.new({
      host: '127.0.0.1',
      port: 50000 - rand(1000),
      username: 'username',
      password: 'password',
      event_handler: -> {}
    })
  end
end
