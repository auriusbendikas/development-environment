# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'
require 'erb'

#Define global confifuration constants
HOSTNAME = "#{`hostname`[0..-2]}".sub(/\..*$/,'')
CONFIG_FILE_PATH = "#{ENV['HOME']}/.development-environment/#{MACHINE}.yml"
CONFIG = Hash.new

#Define default values
CONFIG.merge!({
    'vm_cpu_number' => 2,
    'vm_memory' => 6144,
    'git_user' => `git config user.name`.chomp,
    'git_mail' => `git config user.email`.chomp
})

if File.file?(CONFIG_FILE_PATH)
    puts "Config file \"#{CONFIG_FILE_PATH}\" - loaded."
    FILE_YAML = YAML.load_file("#{ENV['HOME']}/.development-environment/#{MACHINE}.yml")
    unless FILE_YAML.nil? 
        CONFIG.merge!(FILE_YAML)
    end
else
    STDERR.puts "Warining - missing config file \"#{CONFIG_FILE_PATH}\". Using configurations defaults."
end

Vagrant.configure('2') do |config|

    #Configure proxy if proxy.enable is set to true in configuration and remove configuration otherwise
    if Vagrant.has_plugin?('vagrant-proxyconf')
        NO_PROXY = ENV['HTTP_PROXY'].to_s.empty? && ENV['HTTPS_PROXY'].to_s.empty? && ENV['FTP_PROXY'].to_s.empty?

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

        config.vm.provision 'proxy', type:'ansible_local', run: 'always' do |ansible|
            ansible.compatibility_mode = '2.0'
            ansible.playbook = 'scripts/proxy.yml'
            ansible.playbook_command = 'ANSIBLE_ROLES_PATH=$PWD/roles ansible-playbook'
            ansible.extra_vars = {
                proxy_enabled: !NO_PROXY
            }
        end
    else
        raise Vagrant::Errors::VagrantError.new, "Error - plugin missing: vagrant-proxyconf\n\nTo install plugin please execute: vagrant plugin install vagrant-proxyconf"
    end

    # Configure VM to be alligned with hosts timeone
    if Vagrant.has_plugin?('vagrant-timezone')
        config.timezone.value = :host
    else
        raise Vagrant::Errors::VagrantError.new, "Error - plugin missing: vagrant-timezone\n\nTo install plugin please execute: vagrant plugin install vagrant-timezone"
    end

    #Configure autoupdate of guest additions
    if Vagrant.has_plugin?('vagrant-vbguest')
        config.vbguest.auto_update = true
        config.vbguest.no_remote = true
    else
        raise Vagrant::Errors::VagrantError.new, "Error - plugin missing:\n\nTo install plugin please execute: vagrant plugin install vagrant-vbguest"
    end

    #Mashine configuration
    config.vm.box = 'aurius/lubuntu-xenial'
    config.vm.hostname = "#{MACHINE}-#{HOSTNAME}"
    config.vm.synced_folder '../../ansible-roles', '/vagrant/roles', mount_options: ['ro']
    config.vm.synced_folder '../../scripts', '/vagrant/scripts', mount_options: ['ro']

    config.vm.provider 'virtualbox' do |box|
        box.customize ['modifyvm', :id, '--nictype1', 'virtio' ]
        box.customize ['modifyvm', :id, '--macaddress1', 'A80027C32701']
        box.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
        box.customize ['modifyvm', :id, '--natdnsproxy1', 'on']
        box.name = MACHINE
        box.cpus = CONFIG['vm_cpu_number']
        box.memory = CONFIG['vm_memory']
        box.gui = true
    end

    #Fix poluting terminal with wierd error messages
    config.vm.provision 'fix-no-tty', type: 'shell' do |sh|
        sh.privileged = false
        sh.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
    end

    #Copy SSH RSA ID tho guest
    config.vm.provision :file, source: '~/.ssh/id_rsa', destination: '.ssh/id_rsa'

    #Configure bridged networking adapter if 'vm_macaddress' is specified in configuration
    if CONFIG.has_key?('vm_macaddress')
        config.vm.network 'public_network', use_dhcp_assigned_default_route: true
        config.vm.provider 'virtualbox' do |box|
            box.customize ['modifyvm', :id, '--nictype2', 'virtio' ]
            box.customize ['modifyvm', :id, '--macaddress2', CONFIG['vm_macaddress'].delete(':')]
        end

        config.vm.provision 'bridged-networking', type:'ansible_local' do |ansible|
            ansible.compatibility_mode = '2.0'
            ansible.playbook = 'scripts/bridged-networking.yml'
            ansible.extra_vars = CONFIG
        end
    end

end
