require 'logger'
require 'active_support/core_ext'
require 'active_support/json'
require 'active_support/inflector'
require 'active_support/notifications'

module TaxiTwin
  class Log

    include ::Logger::Severity

    attr_reader :logger, :log_prefix

    # creates a new TaxiTwin logger
    # @param [IO,String] log_dev The log device.  This is a filename (String) or IO object (typically +STDOUT+,
    # @param [String] log_prefix String placed in front of every logged message
    #  +STDERR+, or an open file).
    def initialize(log_dev, log_prefix = '[TaxiTwin]')
      if log_dev.kind_of? Logger
        @logger = log_dev
      else
        @logger = Logger.new(log_dev)
      end

      @log_prefix = log_prefix.blank? ? '' : log_prefix.strip

      # subscribe to log messages and send to logger
      @log_subscriber = ActiveSupport::Notifications.subscribe("TaxiTwin.log") do |name, start, finish, id, payload|
        @logger.log(payload[:level], "#{@log_prefix} #{payload[:message]}") if @logger
      end
    end

    def close
      ActiveSupport::Notifications.unsubscribe(@log_subscriber)
    end

    # @param [Logger::Severity] severity
    def level=(severity)
      @logger.level = severity
    end

    # @return [Logger::Severity]
    def level
      @logger.level
    end

    # @see info
    def self.debug(message)
      ActiveSupport::Notifications.instrument("TaxiTwin.log", :level => Logger::DEBUG, :message => message)
    end

    # Log an +INFO+ message
    # @param [String] message the message to log; does not need to be a String
    def self.info(message)
      ActiveSupport::Notifications.instrument("TaxiTwin.log", :level => Logger::INFO, :message => message)
    end

    # @see info
    def self.warn(message)
      ActiveSupport::Notifications.instrument("TaxiTwin.log", :level => Logger::WARN, :message => message)
    end

    # @see info
    def self.error(message)
      ActiveSupport::Notifications.instrument("TaxiTwin.log", :level => Logger::ERROR, :message => message)
    end

    # @see info
    def self.fatal(message)
      ActiveSupport::Notifications.instrument("TaxiTwin.log", :level => Logger::FATAL, :message => message)
    end
  end
end
