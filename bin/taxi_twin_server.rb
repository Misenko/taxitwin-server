#!/usr/bin/env ruby
$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'em-xmpp/connection'
require 'em-xmpp/helpers'

require 'taxi_twin'

logger = TaxiTwin::Log.new(STDOUT)
logger.level = TaxiTwin::Log::DEBUG

GCM_DEBUG = true

SERVER = ENV['SERVER']
PORT = ENV['PORT'].to_i
JID = ENV['JID']
PASSWORD = ENV['PASSWORD']
CERT_DIR = '/etc/ssl/certs'

module GcmClient
  attr_reader :roster

  $DEBUG = GCM_DEBUG

  include EM::Xmpp::XmlParser::Nokogiri
  include EM::Xmpp::Helpers

  def ready
    super
    TaxiTwin::Log.debug 'GcmClient ready'

    on_message do |ctx|
      TaxiTwin::Log.debug "incomming: #{ctx}"
      ctx
    end
  end
end

cfg = {:certificates => CERT_DIR}

trap(:INT) { EM.stop }
trap(:TERM) { EM.stop }
EM.run do
  conn = EM::Xmpp::Connection.start(JID, PASSWORD, GcmClient, cfg, SERVER, PORT)
end

