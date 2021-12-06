require 'spec_helper'
require 'mock_redis'
require 'vmpooler/providers/gce'

RSpec::Matchers.define :relocation_spec_with_host do |value|
  match { |actual| actual[:spec].host == value }
end

describe 'Vmpooler::PoolManager::Provider::Gce' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:poolname) { 'pool1' }
  let(:provider_options) { { 'param' => 'value' } }
  let(:project) { 'dio-samuel-dev' }
  let(:zone){ 'us-west1-b' }
  let(:config) { YAML.load(<<-EOT
---
:config:
  max_tries: 3
  retry_factor: 10
:providers:
  :gce:
    connection_pool_timeout: 1
    project: '#{project}'
    zone: '#{zone}'
    network_name: 'global/networks/default'
:pools:
  - name: '#{poolname}'
    alias: [ 'mockpool' ]
    template: 'projects/debian-cloud/global/images/family/debian-9'
    size: 5
    timeout: 10
    ready_ttl: 1440
    provider: 'gce'
    network_name: 'default'
    machine_type: 'zones/#{zone}/machineTypes/e2-micro'
EOT
    )
  }

  let(:vmname) { 'vm13' }
  let(:connection) { MockComputeServiceConnection.new }
  let(:redis_connection_pool) { Vmpooler::PoolManager::GenericConnectionPool.new(
    metrics: metrics,
    connpool_type: 'redis_connection_pool',
    connpool_provider: 'testprovider',
    size: 1,
    timeout: 5
  ) { MockRedis.new }
  }

  subject { Vmpooler::PoolManager::Provider::Gce.new(config, logger, metrics, redis_connection_pool, 'gce', provider_options) }

  describe '#name' do
    it 'should be gce' do
      expect(subject.name).to eq('gce')
    end
  end

  describe '#manual tests live' do
    skip 'runs in gce' do
      puts "creating"
      result = subject.create_vm(poolname, vmname)
      puts "create disk"
      result = subject.create_disk(poolname, vmname, 10)
      puts "create snapshot"
      result = subject.create_snapshot(poolname, vmname, "sams")
      result = subject.create_snapshot(poolname, vmname, "sams2")
      puts "revert snapshot"
      result = subject.revert_snapshot(poolname, vmname, "sams2")
      #result = subject.destroy_vm(poolname, vmname)
    end

    skip 'runs existing' do
      #result = subject.create_snapshot(poolname, vmname, "sams")
      #result = subject.revert_snapshot(poolname, vmname, "sams")
      #puts subject.get_vm(poolname, vmname)
      result = subject.destroy_vm(poolname, vmname)
    end

    skip 'debug' do

      puts subject.purge_unconfigured_folders(nil, nil, ['foo', '', 'blah'])
    end
  end

  describe '#vms_in_pool' do
    let(:pool_config) { config[:pools][0] }

    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'Given an empty pool folder' do
      it 'should return an empty array' do
        instance_list = MockInstanceList.new(items: nil)
        allow(connection).to receive(:list_instances).and_return(instance_list)
        result = subject.vms_in_pool(poolname)

        expect(result).to eq([])
      end
    end

    context 'Given a pool folder with many VMs' do
      let(:expected_vm_list) {[
        { 'name' => 'vm1'},
        { 'name' => 'vm2'},
        { 'name' => 'vm3'}
      ]}
      before(:each) do
        instance_list = MockInstanceList.new(items: [])
        expected_vm_list.each do |vm_hash|
          mock_vm = MockInstance.new(name: vm_hash['name'])
          instance_list.items << mock_vm
        end

        expect(connection).to receive(:list_instances).and_return(instance_list)
      end

      it 'should list all VMs in the VM folder for the pool' do
        result = subject.vms_in_pool(poolname)

        expect(result).to eq(expected_vm_list)
      end
    end

  end

  describe '#get_vm' do
    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'when VM does not exist' do
      it 'should return nil' do
        allow(connection).to receive(:get_instance).and_raise(create_google_client_error(404,"The resource 'projects/#{project}/zones/#{zone}/instances/#{vmname}' was not found"))
        expect(subject.get_vm(poolname,vmname)).to be_nil
      end
    end

    context 'when VM exists but is missing information' do
      before(:each) do
        allow(connection).to receive(:get_instance).and_return(MockInstance.new(name: vmname))
      end

      it 'should return a hash' do
        expect(subject.get_vm(poolname,vmname)).to be_kind_of(Hash)
      end

      it 'should return the VM name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['name']).to eq(vmname)
      end

      ['hostname','boottime','zone','status'].each do |testcase|
        it "should return nil for #{testcase}" do
          result = subject.get_vm(poolname,vmname)

          expect(result[testcase]).to be_nil
        end
      end
    end

    context 'when VM exists and contains all information' do
      let(:vm_hostname) { "#{vmname}.demo.local" }
      let(:boot_time) { Time.now }
      let(:vm_object) { MockInstance.new(
          name: vmname,
          hostname: vm_hostname,
          labels: {'pool' => poolname},
          creation_timestamp: boot_time,
          status: 'RUNNING',
          zone: zone,
          machine_type: "zones/#{zone}/machineTypes/e2-micro"
        )
      }
      let(:pool_info) { config[:pools][0]}

      before(:each) do
        allow(connection).to receive(:get_instance).and_return(vm_object)
      end

      it 'should return a hash' do
        expect(subject.get_vm(poolname,vmname)).to be_kind_of(Hash)
      end

      it 'should return the VM name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['name']).to eq(vmname)
      end

      it 'should return the VM hostname' do
        result = subject.get_vm(poolname,vmname)

        expect(result['hostname']).to eq(vm_hostname)
      end

      it 'should return the template name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['template']).to eq(pool_info['template'])
      end

      it 'should return the pool name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['poolname']).to eq(pool_info['name'])
      end

      it 'should return the boot time' do
        result = subject.get_vm(poolname,vmname)

        expect(result['boottime']).to eq(boot_time)
      end
    end
  end

  describe '#create_vm' do
    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'Given an invalid pool name' do
      it 'should raise an error' do
        expect{ subject.create_vm('missing_pool', vmname) }.to raise_error(/missing_pool does not exist/)
      end
    end

    context 'Given a template VM that does not exist' do
      before(:each) do
        config[:pools][0]['template'] = 'Templates/missing_template'
=begin
        result = MockResult.new
        result.status = "PENDING"
        errors = MockOperationError
        errors << MockOperationErrorError.new(code: "foo", message: "it's missing")
        result.error = errors
=end
        allow(connection).to receive(:insert_instance).and_raise(create_google_client_error(404,'The resource \'Templates/missing_template\' was not found'))
      end

      it 'should raise an error' do
        expect{ subject.create_vm(poolname, vmname) }.to raise_error(Google::Apis::ClientError, /The resource .+ was not found/)
      end
    end

    context 'Given a successful creation' do

      before(:each) do
        result = MockResult.new
        result.status = "DONE"
        allow(connection).to receive(:insert_instance).and_return(result)
      end

      it 'should return a hash' do
        allow(connection).to receive(:get_instance).and_return(MockInstance.new)
        result = subject.create_vm(poolname, vmname)

        expect(result.is_a?(Hash)).to be true
      end


      it 'should have the new VM name' do
        instance = MockInstance.new(name: vmname)
        allow(connection).to receive(:get_instance).and_return(instance)
        result = subject.create_vm(poolname, vmname)

        expect(result['name']).to eq(vmname)
      end
    end
  end

  describe '#destroy_vm' do
    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'Given a missing VM name' do
      before(:each) do
        allow(connection).to receive(:get_instance).and_raise(create_google_client_error(404,"The resource 'projects/#{project}/zones/#{zone}/instances/#{vmname}' was not found"))
      end

      it 'should return true' do
        expect(subject.destroy_vm(poolname, 'missing_vm')).to be true
      end
    end

    context 'Given a running VM' do
      before(:each) do
        instance = MockInstance.new(name: vmname)
        allow(connection).to receive(:get_instance).and_return(instance)
        result = MockResult.new
        result.status = "DONE"
        allow(subject).to receive(:wait_for_operation).and_return(result)
        allow(connection).to receive(:delete_instance).and_return(result)
      end

      it 'should return true' do
        # no dangling disks
        disk_list = MockDiskList.new(items: nil)
        allow(connection).to receive(:list_disks).and_return(disk_list)
        # no dangling snapshots
        allow(subject).to receive(:find_all_snapshots).and_return(nil)
        expect(subject.destroy_vm(poolname, vmname)).to be true
      end

      it 'should delete any dangling disks' do
        disk = MockDisk.new(name: vmname)
        disk_list = MockDiskList.new(items: [disk])
        allow(connection).to receive(:list_disks).and_return(disk_list)
        # no dangling snapshots
        allow(subject).to receive(:find_all_snapshots).and_return(nil)
        expect(connection).to receive(:delete_disk).with(project, zone, disk.name)
        subject.destroy_vm(poolname, vmname)
      end

      it 'should delete any dangling snapshots' do
        # no dangling disks
        disk_list = MockDiskList.new(items: nil)
        allow(connection).to receive(:list_disks).and_return(disk_list)
        snapshot = MockSnapshot.new(name: "snapshotname-#{vmname}")
        allow(subject).to receive(:find_all_snapshots).and_return([snapshot])
        expect(connection).to receive(:delete_snapshot).with(project, snapshot.name)
        subject.destroy_vm(poolname, vmname)
      end
    end

  end

  describe '#vm_ready?' do
    let(:domain) { nil }
    context 'When a VM is ready' do
      before(:each) do
        expect(subject).to receive(:open_socket).with(vmname, domain)
      end

      it 'should return true' do
        expect(subject.vm_ready?(poolname,vmname)).to be true
      end
    end

    context 'When an error occurs connecting to the VM' do
      before(:each) do
        expect(subject).to receive(:open_socket).and_raise(RuntimeError,'MockError')
      end

      it 'should return false' do
        expect(subject.vm_ready?(poolname,vmname)).to be false
      end
    end
  end

  describe '#create_disk' do
    let(:disk_size) { 10 }
    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'Given an invalid pool name' do
      it 'should raise an error' do
        expect{ subject.create_disk('missing_pool',vmname,disk_size) }.to raise_error(/missing_pool does not exist/)
      end
    end

    context 'when VM does not exist' do
      before(:each) do
        expect(connection).to receive(:get_instance).and_raise(create_google_client_error(404,"The resource 'projects/#{project}/zones/#{zone}/instances/#{vmname}' was not found"))
      end

      it 'should raise an error' do
        expect{ subject.create_disk(poolname,vmname,disk_size) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when adding the disk raises an error' do
      before(:each) do
        disk = MockDisk.new(name: vmname)
        instance = MockInstance.new(name: vmname, disks: [disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        expect(connection).to receive(:insert_disk).and_raise(RuntimeError,'Mock Disk Error')
      end

      it 'should raise an error' do
        expect{ subject.create_disk(poolname,vmname,disk_size) }.to raise_error(/Mock Disk Error/)
      end
    end

    context 'when adding the disk succeeds' do
      before(:each) do
        disk = MockDisk.new(name: vmname)
        instance = MockInstance.new(name: vmname, disks: [disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        result = MockResult.new
        result.status = "DONE"
        allow(connection).to receive(:insert_disk).and_return(result)
        allow(subject).to receive(:wait_for_operation).and_return(result)
        new_disk = MockDisk.new(name: "#{vmname}-disk1", self_link: "/foo/bar/baz/#{vmname}-disk1")
        allow(connection).to receive(:get_disk).and_return(new_disk)
        allow(connection).to receive(:attach_disk).and_return(result)
      end

      it 'should return true' do
        expect(subject.create_disk(poolname,vmname,disk_size)).to be true
      end
    end
  end

  describe '#create_snapshot' do
    let(:snapshot_name) { 'snapshot' }

    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'when VM does not exist' do
      before(:each) do
        allow(connection).to receive(:get_instance).and_raise(create_google_client_error(404,"The resource 'projects/#{project}/zones/#{zone}/instances/#{vmname}' was not found"))
      end

      it 'should raise an error' do
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when snapshot already exists' do
      it 'should raise an error' do
        disk = MockDisk.new(name: vmname)
        instance = MockInstance.new(name: vmname, disks: [disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = [MockSnapshot.new(name: snapshot_name)]
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Snapshot #{snapshot_name} .+ already exists /)
      end
    end

    context 'when snapshot raises an error' do
      before(:each) do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        instance = MockInstance.new(name: vmname, disks: [attached_disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = nil
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        allow(connection).to receive(:create_disk_snapshot).and_raise(RuntimeError,'Mock Snapshot Error')
      end

      it 'should raise an error' do
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Mock Snapshot Error/)
      end
    end

    context 'when snapshot succeeds' do
      before(:each) do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        instance = MockInstance.new(name: vmname, disks: [attached_disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = nil
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        result = MockResult.new
        result.status = "DONE"
        allow(connection).to receive(:create_disk_snapshot).and_return(result)
      end

      it 'should return true' do
        expect(subject.create_snapshot(poolname,vmname,snapshot_name)).to be true
      end

      it 'should snapshot each attached disk' do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        attached_disk2 = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}-disk1")
        instance = MockInstance.new(name: vmname, disks: [attached_disk, attached_disk2])
        allow(connection).to receive(:get_instance).and_return(instance)

        expect(connection.should_receive(:create_disk_snapshot).twice)
        subject.create_snapshot(poolname,vmname,snapshot_name)
      end
    end
  end

  describe '#revert_snapshot' do
    let(:snapshot_name) { 'snapshot' }

    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'when VM does not exist' do
      before(:each) do
        allow(connection).to receive(:get_instance).and_raise(create_google_client_error(404,"The resource 'projects/#{project}/zones/#{zone}/instances/#{vmname}' was not found"))
      end

      it 'should raise an error' do
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when snapshot does not exist' do
      it 'should raise an error' do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        instance = MockInstance.new(name: vmname, disks: [attached_disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = nil
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Snapshot #{snapshot_name} .+ does not exist /)
      end
    end

    context 'when instance does not have attached disks' do
      it 'should raise an error' do
        disk = nil
        instance = MockInstance.new(name: vmname, disks: [disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = [MockSnapshot.new(name: snapshot_name)]
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        allow(connection).to receive(:stop_instance)
        allow(subject).to receive(:wait_for_operation)
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/No disk is currently attached to VM #{vmname} in pool #{poolname}, cannot revert snapshot/)
      end
    end

    context 'when revert to snapshot raises an error' do
      before(:each) do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        instance = MockInstance.new(name: vmname, disks: [attached_disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = [MockSnapshot.new(name: snapshot_name)]
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        allow(connection).to receive(:stop_instance)
        allow(subject).to receive(:wait_for_operation)
        expect(connection).to receive(:detach_disk).and_raise(RuntimeError,'Mock Snapshot Error')
      end

      it 'should raise an error' do
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Mock Snapshot Error/)
      end
    end

    context 'when revert to snapshot succeeds' do
      before(:each) do
        attached_disk = MockAttachedDisk.new(device_name: vmname, source: "foo/bar/baz/#{vmname}")
        instance = MockInstance.new(name: vmname, disks: [attached_disk])
        allow(connection).to receive(:get_instance).and_return(instance)
        snapshots = [MockSnapshot.new(name: snapshot_name, self_link: "foo/bar/baz/snapshot/#{snapshot_name}")]
        allow(subject).to receive(:find_snapshot).and_return(snapshots)
        allow(connection).to receive(:stop_instance)
        allow(subject).to receive(:wait_for_operation)
        allow(connection).to receive(:detach_disk)
        allow(connection).to receive(:delete_disk)
        allow(connection).to receive(:get_snapshot).and_return(snapshots[0])
        new_disk = MockDisk.new(name: vmname, self_link: "foo/bar/baz/disk/#{vmname}")
        allow(connection).to receive(:insert_disk)
        allow(connection).to receive(:get_disk).and_return(new_disk)
        allow(connection).to receive(:attach_disk)
        allow(connection).to receive(:start_instance)
      end

      it 'should return true' do
        expect(subject.revert_snapshot(poolname,vmname,snapshot_name)).to be true
      end
    end
  end

  #TODO: below are todo
  describe '#purge_unconfigured_folders' do
    let(:folder_title) { 'folder1' }
    let(:base_folder) { 'dc1/vm/base' }
    let(:folder_object) { mock_RbVmomi_VIM_Folder({ :name => base_folder }) }
    let(:child_folder) { mock_RbVmomi_VIM_Folder({ :name => folder_title }) }
    let(:whitelist) { nil }
    let(:base_folders) { [ base_folder ] }
    let(:configured_folders) { { folder_title => base_folder } }
    let(:folder_children) { [ folder_title => child_folder ] }
    let(:empty_list) { [] }

    before(:each) do
      allow(subject).to receive(:connect_to_gce).and_return(connection)
    end

    context 'with an empty folder' do
      skip 'should not attempt to destroy any folders' do
        expect(subject).to receive(:get_folder_children).with(base_folder, connection).and_return(empty_list)
        expect(subject).to_not receive(:destroy_folder_and_children)

        subject.purge_unconfigured_folders(base_folders, configured_folders, whitelist)
      end
    end

    skip 'should retrieve the folder children' do
      expect(subject).to receive(:get_folder_children).with(base_folder, connection).and_return(folder_children)
      allow(subject).to receive(:folder_configured?).and_return(true)

      subject.purge_unconfigured_folders(base_folders, configured_folders, whitelist)
    end

    context 'with a folder that is not configured' do
      before(:each) do
        expect(subject).to receive(:get_folder_children).with(base_folder, connection).and_return(folder_children)
        allow(subject).to receive(:folder_configured?).and_return(false)
      end

      skip 'should destroy the folder and children' do
        expect(subject).to receive(:destroy_folder_and_children).with(child_folder).and_return(nil)

        subject.purge_unconfigured_folders(base_folders, configured_folders, whitelist)
      end
    end

    skip 'should raise any errors' do
      expect(subject).to receive(:get_folder_children).and_throw('mockerror')

      expect{ subject.purge_unconfigured_folders(base_folders, configured_folders, whitelist) }.to raise_error(/mockerror/)
    end
  end
  
end
