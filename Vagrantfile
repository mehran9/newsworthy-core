# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = '2'

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.define 'newsworthy-firehorse' do |machine|
    machine.vm.box = 'hashicorp/precise64'
    machine.vm.hostname = 'firehorse.newsworthy.io'
    machine.vm.network 'private_network', ip: '10.0.10.50'
    machine.vm.network 'forwarded_port', guest: 3000, host: 3000
    machine.vm.network 'forwarded_port', guest: 27017, host: 27017

    # machine.vbguest.auto_update = false

    # Share an additional folder to the guest VM. The first argument is
    # the path on the host to the actual folder. The second argument is
    # the path on the guest to mount the folder. And the optional third
    # argument is a set of non-required options.
    # machine.vm.synced_folder '../data', '/vagrant_data'
    # machine.vm.synced_folder('----localfolder-----', '/home/vagrant/code', :nfs => true)

    machine.vm.provision 'puppet' do |puppet|
      puppet.manifests_path = 'vagrant/puppet/manifests'
      puppet.manifest_file = 'default.pp'
      puppet.module_path   = 'vagrant/puppet/modules'
    end

    machine.vm.provision :shell, path: 'vagrant/scripts/bootstrap_rvm.sh', privileged: false
    machine.vm.provision :shell, path: 'vagrant/scripts/bootstrap_locale.sh'
    # machine.vm.provision :shell, inline: 'chmod 644 /etc/mysql/conf.d/vagrant.cnf'

    machine.vm.provider 'virtualbox' do |v|
      v.customize ['modifyvm', :id, '--natdnsproxy1', 'on']
      v.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
      v.customize ['modifyvm', :id, '--rtcuseutc', 'on']

      # Use VBoxManage to customize the VM. For example to change memory:
      v.customize ['modifyvm', :id, '--memory', '2048']
      v.customize ['modifyvm', :id, '--cpuexecutioncap', '95']
    end
  end
end
