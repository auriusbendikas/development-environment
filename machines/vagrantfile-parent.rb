# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'
require 'erb'

#Define global confifuration constants
HOSTNAME = "#{`hostname`[0..-2]}".sub(/\..*$/,'')
CONFIG = YAML.load_file("#{ENV['HOME']}/.development-environment/#{MACHINE}.yml")
PROXY_ENABLED = CONFIG['proxy']['enabled'] == true ? true : false

# Define constants required for proxy configuration
if PROXY_ENABLED
    PROXY_SERVER = "#{CONFIG['proxy']['server']}:#{CONFIG['proxy']['port']}"
    USERNAME = CONFIG['proxy']['username']
    URL_ENCODED_PASSWORD = ERB::Util.url_encode(CONFIG['proxy']['password'])
    HTTP_PROXY = "http://#{USERNAME}:#{URL_ENCODED_PASSWORD}@#{PROXY_SERVER}/"
    NO_PROXY = Array(CONFIG['proxy']['bypass']).inject(StringIO.new) { |buffer, element| buffer << ",#{element}" }.string
else
    HTTP_PROXY=""
end

#Define git user identification constants
GIT_USER = `git config user.name`.chomp
GIT_MAIL = `git config user.email`.chomp

#Merge constants into global connfiguration
CONFIG.merge!({
    git_user: GIT_USER,
    git_mail: GIT_MAIL,
    http_proxy: HTTP_PROXY
})

Vagrant.configure('2') do |config|

    #Configure proxy if proxy.enable is set to true in configuration and remove configuration otherwise
    if Vagrant.has_plugin?('vagrant-proxyconf')
        if PROXY_ENABLED
            config.proxy.http     = HTTP_PROXY
            config.proxy.https    = HTTP_PROXY
            config.proxy.ftp      = HTTP_PROXY
            config.proxy.no_proxy = "localhost,127.0.0.1,#{MACHINE}-#{HOSTNAME}#{NO_PROXY}"
        else
            config.proxy.http     = false
            config.proxy.https    = false
            config.proxy.ftp      = false
            config.proxy.no_proxy = false
        end
    else
        raise Vagrant::Errors::VagrantError.new, 'Plugin missing: vagrant-proxyconf\n\n To install plugin please execute: vagrant plugin install vagrant-proxyconf'
    end

    # Configure VM to be alligned with hosts timeone
    if Vagrant.has_plugin?('vagrant-timezone')
        config.timezone.value = :host
    else
        raise Vagrant::Errors::VagrantError.new, 'Plugin missing: vagrant-timezone\n\n To install plugin please execute: vagrant plugin install vagrant-timezone'
    end

    #Configure autoupdate of guest additions
    if Vagrant.has_plugin?('vagrant-vbguest')
        config.vbguest.auto_update = true
        config.vbguest.no_remote = true
    else
        raise Vagrant::Errors::VagrantError.new, 'Plugin missing: vagrant-vbguest\n\n To install plugin please execute: vagrant plugin install vagrant-vbguest'
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
        box.cpus = 2
        box.memory = 6144
        box.gui = true
    end

    #Fix poluting terminal with wierd error messages
    config.vm.provision 'fix-no-tty', type: 'shell' do |sh|
        sh.privileged = false
        sh.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
    end

    #Copy SSH RSA ID tho guest
    config.vm.provision :file, source: '~/.ssh/id_rsa', destination: '.ssh/id_rsa'

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

end
