# frozen_string_literal: true
require 'googleauth'
require 'google/apis/compute_v1'
require 'bigdecimal'
require 'bigdecimal/util'
require 'vmpooler/providers/base'

module Vmpooler
  class PoolManager
    class Provider
      class Gce < Vmpooler::PoolManager::Provider::Base
        # The connection_pool method is normally used only for testing
        attr_reader :connection_pool

        def initialize(config, logger, metrics, redis_connection_pool, name, options)
          super(config, logger, metrics, redis_connection_pool, name, options)

          task_limit = global_config[:config].nil? || global_config[:config]['task_limit'].nil? ? 10 : global_config[:config]['task_limit'].to_i
          # The default connection pool size is:
          # Whatever is biggest from:
          #   - How many pools this provider services
          #   - Maximum number of cloning tasks allowed
          #   - Need at least 2 connections so that a pool can have inventory functions performed while cloning etc.
          default_connpool_size = [provided_pools.count, task_limit, 2].max
          connpool_size = provider_config['connection_pool_size'].nil? ? default_connpool_size : provider_config['connection_pool_size'].to_i
          # The default connection pool timeout should be quite large - 60 seconds
          connpool_timeout = provider_config['connection_pool_timeout'].nil? ? 60 : provider_config['connection_pool_timeout'].to_i
          logger.log('d', "[#{name}] ConnPool - Creating a connection pool of size #{connpool_size} with timeout #{connpool_timeout}")
          @connection_pool = Vmpooler::PoolManager::GenericConnectionPool.new(
            metrics: metrics,
            connpool_type: 'provider_connection_pool',
            connpool_provider: name,
            size: connpool_size,
            timeout: connpool_timeout
          ) do
            logger.log('d', "[#{name}] Connection Pool - Creating a connection object")
            # Need to wrap the vSphere connection object in another object. The generic connection pooler will preserve
            # the object reference for the connection, which means it cannot "reconnect" by creating an entirely new connection
            # object.  Instead by wrapping it in a Hash, the Hash object reference itself never changes but the content of the
            # Hash can change, and is preserved across invocations.
            new_conn = connect_to_gce
            { connection: new_conn }
          end
          @redis = redis_connection_pool
        end

        # name of the provider class
        def name
          'gce'
        end

        # main configuration options
        def project
          provider_config['project']
        end

        def network_name
          provider_config['network_name']
        end

        # main configuration options, overridable for each pool
        def zone(pool_name)
          return pool_config(pool_name)['zone'] if pool_config(pool_name)['zone']
          return provider_config['zone'] if provider_config['zone']
        end

        def machine_type(pool_name)
          return pool_config(pool_name)['machine_type'] if pool_config(pool_name)['machine_type']
          return provider_config['machine_type'] if provider_config['machine_type']
        end

        #Base methods that are implemented:

        def vms_in_pool(pool_name)
          vms = []
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?
          zone = zone(pool_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            filter = "(labels.pool = #{pool_name})"
            instance_list = connection.list_instances(project, zone, filter: filter)

            return vms if instance_list.items.nil?

            instance_list.items.each do |vm|
              vms << { 'name' => vm.name }
            end
          end
          vms
        end

        # inputs
        #   [String]pool_name : Name of the pool
        #   [String] vm_name  : Name of the VM
        # returns
        #   [String] : Name of the host computer running the vm.  If this is not a Virtual Machine, it returns the vm_name
        def get_vm_host(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement get_vm_host")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to find
        # returns
        #   nil if VM doesn't exist
        #   [Hastable] of the VM
        #    [String] name       : The name of the resource, provided by the client when initially creating the resource
        #    [String] hostname   : Specifies the hostname of the instance. The specified hostname must be RFC1035 compliant. If hostname is not specified,
        #                          the default hostname is [ INSTANCE_NAME].c.[PROJECT_ID].internal when using the global DNS, and
        #                          [ INSTANCE_NAME].[ZONE].c.[PROJECT_ID].internal when using zonal DNS
        #    [String] template   : This is the name of template exposed by the API.  It must _match_ the poolname ??? TODO
        #    [String] poolname   : Name of the pool the VM as per labels
        #    [Time]   boottime   : Time when the VM was created/booted
        #    [String] status     : One of the following values: PROVISIONING, STAGING, RUNNING, STOPPING, SUSPENDING, SUSPENDED, REPAIRING, and TERMINATED
        #    [String] zone       : URL of the zone where the instance resides.
        #  [String] machine_type : Full or partial URL of the machine type resource to use for this instance, in the format: zones/zone/machineTypes/machine-type.
        def get_vm(pool_name, vm_name)
          vm_hash = nil
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            vm_object = connection.get_instance(project, zone(pool_name), vm_name)
            return vm_hash if vm_object.nil?

            vm_hash = generate_vm_hash(vm_object, pool_name)
          end
          vm_hash
        rescue ::Google::Apis::ClientError => e
          raise e unless e.status_code == 404
          #swallow the ClientError error 404 and return nil when the VM was not found
          nil
        end

        # inputs
        #   [String] pool       : Name of the pool
        #   [String] new_vmname : Name to give the new VM
        # returns
        #   [Hashtable] of the VM as per get_vm
        #   Raises RuntimeError if the pool_name is not supported by the Provider
        def create_vm(pool_name, new_vmname)
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?

          vm_hash = nil
          # harcoded network info
          network_interfaces = Google::Apis::ComputeV1::NetworkInterface.new(
            :network => network_name
          )
          initParams = {
            :source_image => pool['template'], #The source image to create this disk.
            :labels => {'vm' => new_vmname, 'pool' => pool_name}
          }
          disk = Google::Apis::ComputeV1::AttachedDisk.new(
            :auto_delete => true,
            :boot => true,
            :initialize_params => Google::Apis::ComputeV1::AttachedDiskInitializeParams.new(initParams)
          )
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            # Assume all pool config is valid i.e. not missing
            template_path = pool['template']
            client = ::Google::Apis::ComputeV1::Instance.new(
              :name => new_vmname,
              :machine_type => pool['machine_type'],
              :disks => [disk],
              :network_interfaces => [network_interfaces],
              :labels => {'pool' => pool_name}
            )
            result = connection.insert_instance(project, zone(pool_name), client)
            result = wait_for_operation(project, pool_name, result, connection)
            if result.error
              error_message = ""
              # array of errors, combine them all
              result.error.each do |error|
                error_message = "#{error_message} #{error.code}:#{error.message}"
              end
              raise "Pool #{pool_name} operation: #{result.description} failed with error: #{error_message}"
            end
            vm_hash = get_vm(pool_name, new_vmname)
          end
          vm_hash
        rescue ::Google::Apis::ClientError => e
          raise e unless e.status_code == 404
          nil
        end

        def create_disk(pool_name, vm_name, disk_size)
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?

          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            begin
              vm_object = connection.get_instance(project, zone(pool_name), vm_name)
            rescue ::Google::Apis::ClientError => e
              raise e unless e.status_code == 404
              #if it does not exist
              raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}")
            end
            # this number should start at 1 when there is only the boot disk,
            # eg the new disk will be named spicy-proton-disk1
            number_disk = vm_object.disks.length()

            disk_name = "#{vm_name}-disk#{number_disk}"
            disk = Google::Apis::ComputeV1::Disk.new(
              :name => disk_name,
              :size_gb => disk_size,
              :labels => {"pool" => pool_name, "vm" => vm_name}
            )
            result = connection.insert_disk(project, zone(pool_name), disk)
            wait_for_operation(project, pool_name, result, connection)
            new_disk = connection.get_disk(project, zone(pool_name), disk_name)

            attached_disk = Google::Apis::ComputeV1::AttachedDisk.new(
              :auto_delete => true,
              :boot => false,
              :source => new_disk.self_link
            )
            result = connection.attach_disk(project, zone(pool_name), vm_object.name, attached_disk)
            wait_for_operation(project, pool_name, result, connection)
            true
          end
          true
        end

        def create_snapshot(pool_name, vm_name, new_snapshot_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            begin
              vm_object = connection.get_instance(project, zone(pool_name), vm_name)
            rescue ::Google::Apis::ClientError => e
              raise e unless e.status_code == 404
              #if it does not exist
              raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}")
            end

            old_snap = find_snapshot(vm_name, new_snapshot_name, connection)
            raise("Snapshot #{new_snapshot_name} for VM #{vm_name} in pool #{pool_name} already exists for the provider #{name}") unless old_snap.nil?

            filter = "(labels.vm = #{vm_name})"
            disk_list = connection.list_disks(project, zone(pool_name), filter: filter)
            result_list = []
            disk_list.items.each do |disk|
              snapshot_obj = ::Google::Apis::ComputeV1::Snapshot.new(
                name: "#{new_snapshot_name}-#{disk.name}",
                labels: {"snapshot_name" => new_snapshot_name, "vm" => vm_name}
              )
              result = connection.create_disk_snapshot(project, zone(pool_name), disk.name, snapshot_obj)
              # do them all async, keep a list, check later
              result_list << result
            end
            #now check they are done
            result_list.each do |result|
              wait_for_operation(project, pool_name, result, connection)
            end
          end
          true
        end

        #TODO
        def revert_snapshot(pool_name, vm_name, snapshot_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            vm_object = connection.get_instance(project, zone(pool_name), vm_name)
            raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if vm_object.nil?

            snapshot_object = find_snapshot(vm_object,name, snapshot_name, connection)
            raise("Snapshot #{snapshot_name} for VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if snapshot_object.nil?

            #TODO part 2
          end
          true
        end

        def destroy_vm(pool_name, vm_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)
            vm_object = connection.get_instance(project, zone(pool_name), vm_name)

            result = connection.delete_instance(project, zone(pool_name), vm_name)
            wait_for_operation(project, pool_name, result, connection, 10)
          end
          true
        rescue ::Google::Apis::ClientError => e
          raise e unless e.status_code == 404
          # If a VM doesn't exist then it is effectively deleted
          true
        end

        def vm_ready?(_pool_name, vm_name)
          begin
            open_socket(vm_name, global_config[:config]['domain'])
          rescue StandardError => _e
            return false
          end

          true
        end

        #TODO
        def purge_unconfigured_folders(base_folders, configured_folders, whitelist)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_gce_connection(pool_object)

            #TODO: part 2 use labels that are not configured
          end
        end

        # END BASE METHODS

        # Compute resource wait for operation to be DONE (synchronous operation)
        def wait_for_operation(project, pool_name, result, connection, retries=5)
          while result.status != 'DONE'
            #logger.log('d',"#{Time.now} (#{retries}) #{result.status}")
            result = connection.wait_zone_operation(project, zone(pool_name), result.name)
          end
          result
        rescue Google::Apis::TransmissionError => e
          # each retry typically about 1 minute.
          if retries > 0
            retries = retries - 1
            retry
          end
          raise
        end

        # Return a hash of VM data
        # Provides vmname, hostname, template, poolname, boottime, status, zone, machine_type information
        def generate_vm_hash(vm_object, pool_name)
          pool_configuration = pool_config(pool_name)
          return nil if pool_configuration.nil?

          {
            'name'         => vm_object.name,
            'hostname'     => vm_object.hostname,
            'template'     => pool_configuration && pool_configuration.key?('template') ? pool_configuration['template'] : nil, #TODO: get it from the API, not from config, but this is what vSphere does too!
            'poolname'     => vm_object.labels && vm_object.labels.key?('pool') ? vm_object.labels['pool'] : nil,
            'boottime'     => vm_object.creation_timestamp,
            'status'       => vm_object.status, # One of the following values: PROVISIONING, STAGING, RUNNING, STOPPING, SUSPENDING, SUSPENDED, REPAIRING, and TERMINATED
            'zone'         => vm_object.zone,
            'machine_type' => vm_object.machine_type
            #'powerstate' => powerstate
          }
        end

        def ensured_gce_connection(connection_pool_object)
          connection_pool_object[:connection] = connect_to_gce unless connection_pool_object[:connection]
          connection_pool_object[:connection]
        end

        def connect_to_gce
          max_tries = global_config[:config]['max_tries'] || 3
          retry_factor = global_config[:config]['retry_factor'] || 10
          try = 1
          begin
            scopes = ["https://www.googleapis.com/auth/compute", "https://www.googleapis.com/auth/cloud-platform"]

            authorization = Google::Auth.get_application_default(scopes)

            compute = ::Google::Apis::ComputeV1::ComputeService.new
            compute.authorization = authorization

            metrics.increment('connect.open')
            compute
          rescue StandardError => e #is that even a thing?
            metrics.increment('connect.fail')
            raise e if try >= max_tries

            sleep(try * retry_factor)
            try += 1
            retry
          end
        end

        # This should supercede the open_socket method in the Pool Manager
        def open_socket(host, domain = nil, timeout = 5, port = 22, &_block)
          Timeout.timeout(timeout) do
            target_host = host
            target_host = "#{host}.#{domain}" if domain
            sock = TCPSocket.new target_host, port
            begin
              yield sock if block_given?
            ensure
              sock.close
            end
          end
        end

        def find_snapshot(vm, snapshotname, connection)
          filter = "(labels.vm = #{vm}) AND (labels.snapshot_name = #{snapshotname})"
          snapshot_list = connection.list_snapshots(project,filter: filter)
          return snapshot_list.items #array of snapshot objects
        end

        #all gce resource names to be RFC1035 compliant
        def safe_name(name)
          name =~ /[a-z]([-a-z0-9]*[a-z0-9])?/
        end
      end
    end
  end
end
