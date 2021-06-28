# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'
require 'erb'

def merge_recursively(target, source)
  target.merge!(source) {|key, target_item, source_item| target_item.is_a?(Hash) ? merge_recursively(target_item, source_item) : source_item }
end

module Vagrant
    module Config
        module V2
            class Root
                def run_ansible(name, playbook, extra_vars, run='once')
                    vm.provision name, type:'ansible_local', run: run do |ansible|
                        ansible.install = false
                        ansible.compatibility_mode = '2.0'
                        ansible.playbook_command = '/opt/ansible-scripts/bin/run-playbook.sh'
                        ansible.inventory_path = '/opt/ansible-scripts/bin/inventory.yaml'
                        ansible.limit = 'localhost'
                        ansible.playbook = playbook
                        ansible.extra_vars = extra_vars
                    end
                end
            end
        end
    end
end

#Define global confifuration constants
HOSTNAME = "#{`hostname`[0..-2]}".sub(/\..*$/,'')
CONFIG_FILE_PATH = "#{ENV['HOME']}/.development-environment/#{MACHINE}.yaml"
CONFIG = Hash.new

#Define default values
CONFIG.merge!({
    'vm_cpus' => 2,
    'vm_memory' => 6144,
    'ansible_scripts_branch' => 'master',
    'git_user' => `git config user.name`.chomp,
    'git_mail' => `git config user.email`.chomp
})

if File.file?(CONFIG_FILE_PATH)
    puts "Config file \"#{CONFIG_FILE_PATH}\" - loaded."
    FILE_YAML = YAML.load_file(CONFIG_FILE_PATH)
    unless FILE_YAML.nil? 
        merge_recursively(CONFIG, FILE_YAML)
    end
else
    STDERR.puts "Warining - missing config file \"#{CONFIG_FILE_PATH}\". Using configurations defaults."
end

Vagrant.configure('2') do |config|

    # Check out latest ansible-scripts project version
    config.vm.provision 'update-ansible-scripts', type:'shell', run: 'always' do |shell|
        shell.path = "../../scripts/update-ansible-scripts.sh"
        shell.args = CONFIG['ansible_scripts_branch']
    end

    NO_PROXY = ENV['HTTP_PROXY'].to_s.empty? && ENV['HTTPS_PROXY'].to_s.empty? && ENV['FTP_PROXY'].to_s.empty?
    if Vagrant.has_plugin?('vagrant-proxyconf')
        # Configure proxy if proxy environment variables are set and remove configuration otherwise
        config.proxy.enabled = { npm: false }
        if NO_PROXY
            config.proxy.http     = false
            config.proxy.https    = false
            config.proxy.ftp      = false
            config.proxy.no_proxy = false
        else
            config.proxy.http     = ENV['HTTP_PROXY']
            config.proxy.https    = ENV['HTTPS_PROXY']
            config.proxy.ftp      = ENV['FTP_PROXY']
            config.proxy.no_proxy = ENV['NO_PROXY'] + ",#{MACHINE}-#{HOSTNAME}"
        end

        config.run_ansible('proxy', '.vagrant/scripts/proxy.yaml', {proxy_enabled: !NO_PROXY}, 'always')
    elsif !NO_PROXY
        raise Vagrant::Errors::VagrantError.new, "Error - plugin missing: vagrant-proxyconf\n\nTo install plugin please execute: vagrant plugin install vagrant-proxyconf"
    end

    # Configure VM to be alligned with hosts timeone
    if Vagrant.has_plugin?('vagrant-timezone')
        config.timezone.value = :host
    else
        raise Vagrant::Errors::VagrantError.new, "Error - plugin missing: vagrant-timezone\n\nTo install plugin please execute: vagrant plugin install vagrant-timezone"
    end

    # Mashine configuration
    config.vm.box = 'aurius/archlinux-zen-uefi'
    config.vm.box_check_update = true
    config.vm.hostname = "#{MACHINE}-#{HOSTNAME}"
    config.vm.synced_folder '../../scripts', '/vagrant/.vagrant/scripts', mount_options: ['ro']

    config.vm.provider 'virtualbox' do |box|
        box.customize ['modifyvm', :id, '--vram', '128']
        box.customize ['modifyvm', :id, '--nictype1', 'virtio']
        box.customize ['modifyvm', :id, '--macaddress1', 'A80027C32701']
        box.customize ['modifyvm', :id, '--natdnshostresolver1', 'off']
        box.customize ['modifyvm', :id, '--natdnsproxy1', 'off']
        box.name = MACHINE
        box.cpus = CONFIG['vm_cpus']
        box.memory = CONFIG['vm_memory']
        box.gui = true
    end

    # Copy SSH RSA ID to guest
    config.vm.provision 'file', source: '~/.ssh/id_rsa', destination: '.ssh/id_rsa'
    config.vm.provision 'file', source: '~/.ssh/id_rsa.pub', destination: '.ssh/id_rsa.pub'

    # Configure bridged networking adapter if 'vm_macaddress' is specified in configuration
    if CONFIG.has_key?('vm_macaddress')
        config.vm.network 'public_network', use_dhcp_assigned_default_route: true
        config.vm.provider 'virtualbox' do |box|
            box.customize ['modifyvm', :id, '--nictype2', 'virtio' ]
            box.customize ['modifyvm', :id, '--macaddress2', CONFIG['vm_macaddress'].delete(':')]
        end

        config.run_ansible('bridged-networking', '.vagrant/scripts/bridged-networking.yaml', CONFIG)
    end
end
