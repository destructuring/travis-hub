require 'multi_json'

require 'travis'
require 'travis/model'
require 'travis/states_cache'
require 'travis/support/amqp'
require 'travis/hub/queue'
require 'travis/hub/error'
require 'core_ext/kernel/run_periodically'

$stdout.sync = true

module Travis
  class Hub
    def setup
      Travis::Async.enabled = true
      Travis::Amqp.config = Travis.config.amqp

      Travis::Database.connect
      if Travis.config.logs_database
        Log.establish_connection 'logs_database'
        Log::Part.establish_connection 'logs_database'
      end

      Travis::Async::Sidekiq.setup(Travis.config.redis.url, Travis.config.sidekiq)

      Travis::Exceptions::Reporter.start
      Travis::Metrics.setup
      Travis::Notification.setup
      Travis::Addons.register

      Travis::Memory.new(:hub).report_periodically if Travis.env == 'production' && Travis.config.metrics.report
      NewRelic.start if File.exists?('config/newrelic.yml')
    end

    def run
      enqueue_jobs
      Queue.subscribe(&method(:handle))
    end

    private

      def handle(event, payload)
        ActiveRecord::Base.cache do
          Travis.run_service(:update_job, event: event.to_s.split(':').last, data: payload)
        end
      end

      def enqueue_jobs
        run_periodically(Travis.config.queue.interval) do
          begin
            Travis.run_service(:enqueue_jobs) unless Travis::Features.feature_active?(:travis_enqueue)
          rescue => e
            Travis.logger.log_exception(e)
          end
        end
      end
  end
end
