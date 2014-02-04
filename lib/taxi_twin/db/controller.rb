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
        create_indexes
      end

      def drop_tables
        run_sql_from_file 'drop.sql'
      end

      def create_indexes
        connection.prepare("check_index", "SELECT * FROM pg_class WHERE relname = $1")
        f = open_sql_file('index.sql')
        f.each_line do |line|
          split = line.split '$'
          unless connection.exec_prepared("check_index", split.take(1)).any?
            connection.exec(split.last)
          end
        end
        f.close
      end

      def run_sql_from_file(filename)
        f = open_sql_file(filename)
        f.each_line do |line|
          connection.exec(line)
        end
        f.close
      end

      def open_sql_file(filename)
        File.open(File.join(File.dirname(__FILE__), 'sql', filename), 'r')
      end
    end
  end
end

