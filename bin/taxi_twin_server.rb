#!/usr/bin/env ruby
$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'em-xmpp/connection'

require 'taxi_twin'

logger = TaxiTwin::Log.new(STDOUT)
logger.level = TaxiTwin::Log::DEBUG

SERVER = ENV['SERVER']
PORT = ENV['PORT'].to_i
JID = ENV['JID']
PASSWORD = ENV['PASSWORD']
CERT_DIR = '/etc/ssl/certs'

cfg = {:certificates => CERT_DIR}

trap(:INT) { EM.stop }
trap(:TERM) { EM.stop }
EM.run do
  conn = EM::Xmpp::Connection.start(JID, PASSWORD, TaxiTwin::Gcm::Client, cfg, SERVER, PORT)
end

