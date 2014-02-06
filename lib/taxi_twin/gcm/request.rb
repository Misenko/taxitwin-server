require 'json'
require 'nokogiri'
#require 'gcoder'

require 'em-xmpp/connection'

module TaxiTwin
  module Gcm
    class Request
      attr_reader :client, :data, :type, :tt_data

      def initialize(client, data)
        @client = client
        @data = data
        @tt_data = data['data']
        @type = tt_data['type'].to_sym if tt_data.has_key? 'type'
      end

      def respond
        case type
        when :subscribe
          subscribe
        else
          invalid_request_type
        end
      end

      def subscribe
        start_long = tt_data['start_long'].to_f
        start_lat = tt_data['start_lat'].to_f
        end_long = tt_data['end_long'].to_f
        end_lat = tt_data['end_lat'].to_f
        radius = tt_data['radius'].to_f/100000
        from = data['from']
        name = tt_data['name']
        passengers = tt_data['passengers']

        dc = TaxiTwin::Db::Controller.new
        dc.load_data_on_subscribe(start_long, start_lat, end_long, end_lat, radius) do |row|
          send_response row
        end

        device_id = dc.exists?('device', {'google_id' => from})
        unless device_id
          tmp = {}
          tmp['google_id'] = from
          tmp['name'] = name
          device_id = dc.store_data('device', tmp)
        end

        gcoder = GCoder.connect
        start_textual = gcoder[[start_lat, start_long]][0]['formatted_address']
        end_textual = gcoder[[end_lat, end_long]][0]['formatted_address']

        start_id = dc.exists?('point', {'longitude' => start_long, 'latitude' => start_lat})
        unless start_id
          tmp = {}
          tmp['longitude'] = start_long
          tmp['latitude'] = start_lat
          tmp['textual'] = start_textual
          start_id = dc.store_data('point', tmp)
        end

        end_id = dc.exists?('point', {'longitude' => end_long, 'latitude' => end_lat})
        unless end_id
          tmp = {}
          tmp['longitude'] = end_long
          tmp['latitude'] = end_lat
          tmp['textual'] = end_textual
          end_id = dc.store_data('point', tmp)
        end

        tmp = {}
        tmp['device_id'] = device_id
        tmp['start_point_id'] = start_id
        tmp['end_point_id'] = end_id
        tmp['radius'] = radius
        tmp['passengers'] = passengers
        dc.store_data('taxitwin', tmp)

        ###TODO###
        #check wether this new taxitwin is a good match for some taxitwins already in db
        #if so send them this new taxitwin
      end

      def send_response(message_data)
        message = {}
        message['to'] = data['from']
        message['message_id'] = MessageIdHandler.instance.next_id
        message['time_to_live'] = 600
        message['data'] = message_data
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm(JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        if Queue.instance.free_space > 0
          Queue.instance.add_nonacked_message(message)
          client.send_raw builder.to_xml
        else
          TaxiTwin::Log.error "full queue, cannot send message: #{builder.to_xml}"
        end
      end

      def invalid_request_type
        TaxiTwin::Log.error "invalid request: #{data}"
      end

      def send_ack
        message = {}
        message['to'] = data['from']
        message['message_id'] = data['message_id']
        message['message_type'] = 'ack'
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm( JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        client.send_raw builder.to_xml
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
