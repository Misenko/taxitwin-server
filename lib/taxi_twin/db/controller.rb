require 'pg'

module TaxiTwin
  module Db
    class Controller
      attr_accessor :connection

      def connect
        @connection = PG.connect(
        :dbname => ENV['DB_NAME'],
        :user => ENV['DB_USER'],
        :password => ENV['DB_PASS'])
      end

      def disconnect
        connection.close
      end

      def create_tables
        run_sql_from_file 'create.sql'
      end

      def drop_tables
        run_sql_from_file 'drop.sql'
      end

      def run_sql_from_file(filename)
        f = File.open(File.join(File.dirname(__FILE__), 'sql', filename), 'r')
        f.each_line do |line|
          connection.exec(line)
        end
        f.close
      end
    end
  end
end

