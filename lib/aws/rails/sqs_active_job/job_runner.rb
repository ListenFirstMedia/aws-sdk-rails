# frozen_string_literal: true

module Aws
  module Rails
    module SqsActiveJob
      class JobRunner
        attr_reader :id, :class_name

        def initialize(message)
          @job_data = Aws::Json.load(message.data.body)
          @class_name = @job_data['job_class'].constantize
          @id = @job_data['job_id']
        end

        def run
          ActiveJob::Base.execute @job_data
        ensure
          clear_connections!
        end

        private

        # Don't have to deal with ActiveRecord::Base#with_connection.
        def clear_connections!
          return unless defined?(::ActiveRecord::Base)

          if ::ActiveRecord.version >= Gem::Version.new('7.1')
            ::ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
          else
            ::ActiveRecord::Base.clear_active_connections!
          end
        end
      end
    end
  end
end
