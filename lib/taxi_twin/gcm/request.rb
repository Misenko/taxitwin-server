require 'json'
require 'nokogiri'

require 'em-xmpp/connection'

module TaxiTwin
  module Gcm
    class Request
      attr_reader :data

      def initialize(data)
        @data = data
      end

      def ack_response
        message = {}
        message['to'] = data['from']
        message['message_id'] = data['message_id']
        message['message_type'] = 'ack'
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm( JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        builder.to_xml
      end

      def dummy_response
        message = {}
        message['to'] = data['from']
        message['message_id'] = MessageIdHandler.instance.next_id
        message['time_to_live'] = 600
        message['data'] = {'ruby' => 'rocks!'}
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm(JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        Queue.instance.add_nonacked_message(message)
        builder.to_xml
      end
    end
  end
end
