# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'
require 'erb'

HOSTNAME = "#{`hostname`[0..-2]}".sub(/\..*$/,'')
CONFIG = YAML.load_file("#{ENV['HOME']}/.development-environment/#{MACHINE}.yml")
PROXY_ENABLED = CONFIG['proxy']['enabled']

if PROXY_ENABLED
    PROXY_SERVER = "#{CONFIG['proxy']['server']}:#{CONFIG['proxy']['port']}"
    USERNAME = CONFIG['proxy']['username']
    URL_ENCODED_PASSWORD = ERB::Util.url_encode(CONFIG['proxy']['password'])
    HTTP_PROXY = "http://#{USERNAME}:#{URL_ENCODED_PASSWORD}@#{PROXY_SERVER}/"
else
    HTTP_PROXY=""
end

GIT_USER = `git config user.name`.chomp
GIT_MAIL = `git config user.email`.chomp

CONFIG.merge!({
    git_user: GIT_USER,
    git_mail: GIT_MAIL,
    http_proxy: HTTP_PROXY
})

Vagrant.configure('2') do |config|
    config.vbguest.auto_update = true
    config.vbguest.no_remote = true
    config.vm.box_download_insecure = true
    config.vm.box_download_location_trusted = true
    config.vm.box = 'aurius/lubuntu-xenial'
    config.vm.hostname = "#{MACHINE}-#{HOSTNAME}"
    config.vm.synced_folder '../../ansible-roles', '/vagrant/roles', mount_options: ['ro']
    config.vm.synced_folder '../../scripts', '/vagrant/scripts', mount_options: ['ro']

    config.vm.provision 'fix-no-tty', type: 'shell' do |sh|
        sh.privileged = false
        sh.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
    end

    config.vm.provision 'install-ansible', type:'shell' do |sh|
        sh.path = '../../scripts/install-ansible.sh'
        sh.env = {
            http_proxy: HTTP_PROXY,
            https_proxy: HTTP_PROXY
        }
    end

    #Configure bridged networking adapter if 'macaddress' is specified in configuration
    if CONFIG.has_key?('macaddress')
        config.vm.network 'public_network', use_dhcp_assigned_default_route: true
        config.vm.provider 'virtualbox' do |box|
            box.customize ['modifyvm', :id, '--nictype2', 'virtio' ]
            box.customize ['modifyvm', :id, '--macaddress2', CONFIG['macaddress'].delete(':')]
        end

        config.vm.provision 'bridged-networking', type:'ansible_local' do |ansible|
            ansible.playbook = 'scripts/bridged-networking.yml'
            ansible.extra_vars = CONFIG
        end
    end

    config.vm.provision :file, source: '~/.ssh/id_rsa', destination: '.ssh/id_rsa'

    config.timezone.value = :host

    config.vm.provider 'virtualbox' do |box|
        box.customize ['modifyvm', :id, '--nictype1', 'virtio' ]
        box.customize ['modifyvm', :id, '--macaddress1', 'A80027C32701']
        box.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
        box.customize ['modifyvm', :id, '--natdnsproxy1', 'on']
        box.name = MACHINE
        box.cpus = 2
        box.memory = 6144
        box.gui = true
    end
end