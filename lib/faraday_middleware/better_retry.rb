# -*- encoding : utf-8 -*-
require 'ostruct'
module FaradayMiddleware
  # Catches exceptions and retries each request a limited number of times.
  #
  # By default, it retries 2 times and handles only timeout exceptions. It can
  # be configured with an arbitrary number of retries, a list of exceptions to
  # handle an a retry interval.
  #
  # Examples
  #
  #   Faraday.new do |conn|
  #     conn.request :retry, max: 2, interval: 0.05,
  #                          exceptions: [CustomException, 'Timeout::Error']
  #     conn.adapter ...
  #   end
  class BetterRetry < Faraday::Middleware
    class Options < OpenStruct

      def max
        (self[:max] ||= 2).to_i
      end

      def interval
        (self[:interval] ||= 0).to_f
      end

      def exceptions
        Array(self[:exceptions] ||= [Errno::ETIMEDOUT, 'Timeout::Error', Error::TimeoutError])
      end

      # define for ruby less than 2.0
      def [](name)
        @table[name.to_sym]
      end

      def []=(name, value)
        modifiable[new_ostruct_member(name)] = value
      end

    end

    # Public: Initialize middleware
    #
    # Options:
    # max        - Maximum number of retries (default: 2).
    # interval   - Pause in seconds between retries (default: 0).
    # exceptions - The list of exceptions to handle. Exceptions can be
    #              given as Class, Module, or String. (default:
    #              [Errno::ETIMEDOUT, Timeout::Error, Error::TimeoutError])
    def initialize(app, options = {})
      super(app)
      @options = Options.new(options)
      @errmatch = build_exception_matcher(@options.exceptions)
      @logger = options[:logger]
    end

    def call(env)
      env[:retries] = retries = @options.max
      begin
        @app.call(env)
      rescue @errmatch => e
        if retries > 0
          if @logger
            @logger.warn("Retrying Parse Error #{e.inspect} on request #{env[:url].to_s} #{env[:body].inspect} response #{env[:response].inspect}")
          end
          retries -= 1
          env[:retries] = retries
          sleep @options.interval if @options.interval > 0
          retry
        end
        raise
      end
    end

    # Private: construct an exception matcher object.
    #
    # An exception matcher for the rescue clause can usually be any object that
    # responds to `===`, but for Ruby 1.8 it has to be a Class or Module.
    def build_exception_matcher(exceptions)
      matcher = Module.new
      (class << matcher; self; end).class_eval do
        define_method(:===) do |error|
          exceptions.any? do |ex|
            if ex.is_a? Module then error.is_a? ex
            else error.class.to_s == ex.to_s
            end
          end
        end
      end
      matcher
    end
  end
end
