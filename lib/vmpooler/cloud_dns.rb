# frozen_string_literal: true

require 'googleauth'
require 'google/cloud/dns'

module Vmpooler
  class PoolManager
    # This class interacts with GCP Cloud DNS to create or delete records.
    class CloudDns
      def initialize(project, dns_zone_resource_name)
        @dns = Google::Cloud::Dns.new(project_id: project)
        @dns_zone_resource_name = dns_zone_resource_name
      end

      def dns_create_or_replace(created_instance)
        dns_zone = @dns.zone(@dns_zone_resource_name) if @dns_zone_resource_name
        return unless dns_zone && created_instance && created_instance['name'] && created_instance['ip']

        retries = 0
        name = created_instance['name']
        begin
          change = dns_zone.add(name, 'A', 60, [created_instance['ip']])
          debug_logger("#{change.id} - #{change.started_at} - #{change.status} DNS address added") if change
        rescue Google::Cloud::AlreadyExistsError => _e
          # DNS setup is done only for new instances, so in the rare case where a DNS record already exists (it is stale) and we replace it.
          # the error is Google::Cloud::AlreadyExistsError: alreadyExists: The resource 'entity.change.additions[0]' named 'instance-8.test.vmpooler.net. (A)' already exists
          change = dns_zone.replace(name, 'A', 60, [created_instance['ip']])
          debug_logger("#{change.id} - #{change.started_at} - #{change.status} DNS address previously existed and was replaced") if change
        rescue Google::Cloud::FailedPreconditionError => e
          # this error was experienced intermittently, will retry to see if it can complete successfully
          # the error is Google::Cloud::FailedPreconditionError: conditionNotMet: Precondition not met for 'entity.change.deletions[0]'
          debug_logger("DNS create failed, retrying error: #{e}")
          sleep 5
          retry if (retries += 1) < 30
        end
      end

      def dns_teardown(created_instance)
        dns_zone = @dns.zone(@dns_zone_resource_name) if @dns_zone_resource_name
        return unless dns_zone && created_instance

        retries = 0
        name = created_instance['name']
        change = dns_zone.remove(name, 'A')
        debug_logger("#{change.id} - #{change.started_at} - #{change.status} DNS address removed") if change
      rescue Google::Cloud::FailedPreconditionError => e
        # this error was experienced intermittently, will retry to see if it can complete successfully
        # the error is Google::Cloud::FailedPreconditionError: conditionNotMet: Precondition not met for 'entity.change.deletions[1]'
        debug_logger("DNS teardown failed, retrying error: #{e}")
        sleep 5
        retry if (retries += 1) < 30
      end

      # used in local dev environment, set DEBUG_FLAG=true
      # this way the upstream vmpooler manager does not get polluted with logs
      def debug_logger(message, send_to_upstream: false)
        # the default logger is simple and does not enforce debug levels (the first argument)
        puts message if ENV['DEBUG_FLAG']
        logger.log('[g]', message) if send_to_upstream
      end
    end
  end
end
