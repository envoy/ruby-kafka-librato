# frozen_string_literal: true

require "kafka/librato/version"
require "active_support/subscriber"

module Kafka
  module Librato
    class LibratoSubscriber < ActiveSupport::Subscriber
      private

      %w[increment measure timing].each do |type|
        define_method(type) do |metric, *args|
          ::Librato.send(type, "kafka.#{metric}", *args)
        end
      end

      def without_prefix(topic)
        prefix = ENV["KAFKA_PREFIX"]
        topic.gsub(/\A#{prefix}/, "")
      end
    end

    class ConnectionSubscriber < LibratoSubscriber
      def request(event)
        client = event.payload.fetch(:client_id)
        api = event.payload.fetch(:api, "unknown")
        request_size = event.payload.fetch(:request_size, 0)
        response_size = event.payload.fetch(:response_size, 0)
        broker = event.payload.fetch(:broker_host)

        options = {
          tags: {
            client: client,
            api:    api,
            broker: broker
          }
        }

        timing("api.latency", event.duration, options)
        increment("api.calls", options)
        measure("api.request_size", request_size, options)
        measure("api.response_size", response_size, options)

        if event.payload.key?(:exception)
          increment("api.errors", options)
        end
      end

      attach_to "connection.kafka"
    end

    class ConsumerSubscriber < LibratoSubscriber
      def process_message(event)
        offset_lag = event.payload.fetch(:offset_lag)
        create_time = event.payload.fetch(:create_time)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)
        topic = event.payload.fetch(:topic)
        partition = event.payload.fetch(:partition)

        time_lag = create_time && ((Time.now.utc - create_time) * 1000).to_i

        options = {
          tags: {
            client:    client,
            group_id:  group_id,
            topic:     without_prefix(topic),
            partition: partition
          }
        }

        if event.payload.key?(:exception)
          increment("consumer.process_message.errors", options)
        else
          timing("consumer.process_message.latency", event.duration, options)
          increment("consumer.messages", options)
        end

        measure("consumer.lag", offset_lag, options)

        # Not all messages have timestamps.
        if time_lag
          timing("consumer.time_lag", time_lag, options)
        end
      end

      def process_batch(event)
        lag = event.payload.fetch(:offset_lag)
        messages = event.payload.fetch(:message_count)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)
        topic = event.payload.fetch(:topic)
        partition = event.payload.fetch(:partition)

        options = {
          tags: {
            client:    client,
            group_id:  group_id,
            topic:     without_prefix(topic),
            partition: partition
          }
        }

        if event.payload.key?(:exception)
          increment("consumer.process_batch.errors", options)
        else
          timing("consumer.process_batch.latency", event.duration, options)
          increment("consumer.messages", options.merge(by: messages))
        end

        measure("consumer.lag", lag, options)
      end

      def join_group(event)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)

        options = {
          tags: {
            client:   client,
            group_id: group_id
          }
        }

        timing("consumer.join_group", event.duration, options)

        if event.payload.key?(:exception)
          increment("consumer.join_group.errors", options)
        end
      end

      def sync_group(event)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)

        options = {
          tags: {
            client:   client,
            group_id: group_id
          }
        }

        timing("consumer.sync_group", event.duration, options)

        if event.payload.key?(:exception)
          increment("consumer.sync_group.errors", options)
        end
      end

      def leave_group(event)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)

        options = {
          tags: {
            client:   client,
            group_id: group_id
          }
        }

        timing("consumer.leave_group", event.duration, options)

        if event.payload.key?(:exception)
          increment("consumer.leave_group.errors", options)
        end
      end

      def pause_status(event)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)
        topic = event.payload.fetch(:topic)
        partition = event.payload.fetch(:partition)

        duration = event.payload.fetch(:duration)

        options = {
          tags: {
            client:    client,
            group_id:  group_id,
            topic:     without_prefix(topic),
            partition: partition
          }
        }

        measure("consumer.pause.duration", duration, options)
      end

      attach_to "consumer.kafka"
    end

    class ProducerSubscriber < LibratoSubscriber
      def produce_message(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)
        message_size = event.payload.fetch(:message_size)
        buffer_size = event.payload.fetch(:buffer_size)
        max_buffer_size = event.payload.fetch(:max_buffer_size)
        buffer_fill_ratio = buffer_size.to_f / max_buffer_size.to_f
        buffer_fill_percentage = buffer_fill_ratio * 100.0

        options = {
          tags: {
            client: client
          }
        }
        options_with_topic = options.deep_merge({
          tags: {
            topic: without_prefix(topic)
          }
        })

        # This gets us the write rate.
        increment("producer.produce.messages", options_with_topic)

        measure("producer.produce.message_size", message_size, options_with_topic)

        # This gets us the avg/max buffer size per producer.
        measure("producer.buffer.size", buffer_size, options)

        # This gets us the avg/max buffer fill ratio per producer.
        measure("producer.buffer.fill_ratio", buffer_fill_ratio, options)
        measure("producer.buffer.fill_percentage", buffer_fill_percentage, options)
      end

      def buffer_overflow(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)

        options = {
          tags: {
            client: client,
            topic:  without_prefix(topic)
          }
        }

        increment("producer.produce.errors", options)
      end

      def deliver_messages(event)
        client = event.payload.fetch(:client_id)
        message_count = event.payload.fetch(:delivered_message_count)
        attempts = event.payload.fetch(:attempts)

        options = {
          tags: {
            client: client
          }
        }

        if event.payload.key?(:exception)
          increment("producer.deliver.errors", options)
        end

        timing("producer.deliver.latency", event.duration, options)

        # Messages delivered to Kafka:
        increment("producer.deliver.messages", options.merge(by: message_count))

        # Number of attempts to deliver messages:
        measure("producer.deliver.attempts", attempts, options)
      end

      def ack_message(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)

        options = {
          tags: {
            client: client,
            topic:  without_prefix(topic)
          }
        }

        # Number of messages ACK'd for the topic.
        increment("producer.ack.messages", options)

        # Histogram of delay between a message being produced and it being ACK'd.
        timing("producer.ack.delay", event.payload.fetch(:delay), options)
      end

      def topic_error(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)

        options = {
          tags: {
            client: client,
            topic:  without_prefix(topic)
          }
        }

        increment("producer.ack.errors", options)
      end

      attach_to "producer.kafka"
    end

    class AsyncProducerSubscriber < LibratoSubscriber
      def enqueue_message(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)
        queue_size = event.payload.fetch(:queue_size)
        max_queue_size = event.payload.fetch(:max_queue_size)
        queue_fill_ratio = queue_size.to_f / max_queue_size.to_f

        options = {
          tags: {
            client: client,
            topic:  without_prefix(topic)
          }
        }

        # This gets us the avg/max queue size per producer.
        measure("async_producer.queue.size", queue_size, options)

        # This gets us the avg/max queue fill ratio per producer.
        measure("async_producer.queue.fill_ratio", queue_fill_ratio, options)
      end

      def buffer_overflow(event)
        client = event.payload.fetch(:client_id)
        topic = event.payload.fetch(:topic)

        options = {
          tags: {
            client: client,
            topic:  without_prefix(topic)
          }
        }

        increment("async_producer.produce.errors", options)
      end

      def drop_messages(event)
        client = event.payload.fetch(:client_id)
        message_count = event.payload.fetch(:message_count)

        options = {
          tags: {
            client: client
          }
        }

        increment("async_producer.dropped_messages", options.merge(by: message_count))
      end

      attach_to "async_producer.kafka"
    end

    class FetcherSubscriber < LibratoSubscriber
      def loop(event)
        queue_size = event.payload.fetch(:queue_size)
        client = event.payload.fetch(:client_id)
        group_id = event.payload.fetch(:group_id)

        options = {
          tags: {
            client:   client,
            group_id: group_id
          }
        }

        measure("fetcher.queue_size", queue_size, options)
      end

      attach_to "fetcher.kafka"
    end
  end
end
