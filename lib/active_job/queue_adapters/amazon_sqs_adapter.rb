# frozen_string_literal: true

require 'aws-sdk-sqs'

module ActiveJob
  module QueueAdapters
    class AmazonSqsAdapter
      def enqueue(job)
        _enqueue(job)
      end

      def enqueue_at(job, timestamp)
        delay = (timestamp - Time.now.to_f).floor
        raise ArgumentError, 'Unable to queue a job with a delay great than 15 minutes' if delay > 15.minutes

        _enqueue(job, nil, delay_seconds: delay)
      end

      private

      def _enqueue(job, body = nil, send_message_opts = {})
        body ||= job.serialize
        queue_url = Aws::Rails::SqsActiveJob.config.queue_url_for(job.queue_name)
        send_message_opts[:queue_url] = queue_url
        send_message_opts[:message_body] = Aws::Json.dump(body)
        send_message_opts[:message_attributes] = message_attributes(job)

        if Aws::Rails::SqsActiveJob.fifo?(queue_url)
          send_message_opts[:message_deduplication_id] =
            Digest::SHA256.hexdigest(Aws::Json.dump(deduplication_body(job, body)))

          message_group_id = job.message_group_id if job.respond_to?(:message_group_id)
          message_group_id ||= Aws::Rails::SqsActiveJob.config.message_group_id

          send_message_opts[:message_group_id] = message_group_id
        end

        Rails.logger.info("Enqueueing message: #{send_message_opts}")
        msg_resp = Aws::Rails::SqsActiveJob.config.client.send_message(send_message_opts)
        Rails.logger.info("Received response from SQS client: #{msg_resp}")
        raise 'Message not enqueued' if !msg_resp.respond_to?(:message_id) || msg_resp.message_id.empty?
        msg_resp
      rescue StandardError => e
        raise ActiveJob::EnqueueError.new(e.message)
      end

      def message_attributes(job)
        {
          'aws_sqs_active_job_class' => {
            string_value: job.class.to_s,
            data_type: 'String'
          },
          'aws_sqs_active_job_version' => {
            string_value: Aws::Rails::VERSION,
            data_type: 'String'
          }
        }
      end

      def deduplication_body(job, body)
        ex_dedup_keys = job.excluded_deduplication_keys if job.respond_to?(:excluded_deduplication_keys)
        ex_dedup_keys ||= Aws::Rails::SqsActiveJob.config.excluded_deduplication_keys

        body.except(*ex_dedup_keys)
      end
    end

    # create an alias to allow `:amazon` to be used as the adapter name
    # `:amazon` is the convention used for ActionMailer and ActiveStorage
    AmazonAdapter = AmazonSqsAdapter
  end
end
