#!/bin/bash -e

cat <<EOF > /etc/apt/apt.conf
Acquire::http::proxy "$http_proxy";
Acquire::https::proxy "$http_proxy";
Acquire::ftp::proxy "$http_proxy";
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install software-properties-common -y
add-apt-repository ppa:ansible/ansible -y
apt-get update -y
apt-get dist-upgrade -y
apt-get install ansible -y
