#!/usr/bin/evn ruby
# frozen_string_literal: true

# control-plane node(s)
control_plans_ports = {
  "2379": 'etcd server client api',
  "2380": 'etcd server client api',
  "10205": 'kubelet api',
  "10251": 'kube-scheduler',
  "10252": 'kube-controller-manager'
}
# kubernetes api server
(64_430..64_439).to_a.each do |port|
  control_plans_ports[port.to_s] = 'kubernetes api server'
end

# worker nodes(s)
worker_ports = {
  '10250': 'kubelet api'
}
# NodePort Servicest
(30_000..32_767).to_a.each do |port|
  worker_ports[port.to_s] = 'NodePort Servicest'
end

proxy_host = "10.11.1.147"
proxy_port = 8118

puts '# Installing kubeadm on ubuntu'

puts "=> set apt proxy: http://#{proxy_host}:#{proxy_port}"
puts `export http_proxy="http://#{proxy_host}:#{proxy_port}"; https_proxy="http://#{proxy_host}:#{proxy_port}"`

apt_proxy_config = '/etc/apt/apt.conf.d/05proxy'
unless File.exist? apt_proxy_config
  handle = File.new apt_proxy_config, 'w+'
  handle.write "Acquire::http::Proxy \"http://#{proxy_host}:#{proxy_port}\";\n"
  handle.write "Acquire::https::Proxy \"http://#{proxy_host}:#{proxy_port}\";\n"
  handle.close
end

puts '=> Verify the MAC address and product_uuid'
puts `ip link`
puts `cat /sys/class/dmi/id/product_uuid`

puts '=> Check network adapters'

puts `which netstat`
if $?.exitstatus.to_i != 0
  puts "you need to install net-tools, use: 'sudo apt install -y net-tools'"
  exit 1
end

k8s_config_module_load = '/etc/modules-load.d/k8s.conf'
k8s_config_sysctl = '/etc/sysctl.d/k8s.conf'

puts "generate k8s.conf [#{k8s_config_module_load}, #{k8s_config_sysctl}].. "
unless File.exist? k8s_config_module_load
  # cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
  # br_netfilter
  # EOF
  handle = File.new k8s_config_module_load, 'w+'
  handle.write 'br_netfilter'
  handle.flush
  handle.close
end

unless File.exist? k8s_config_sysctl
  # cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
  # net.bridge.bridge-nf-call-ip6tables = 1
  # net.bridge.bridge-nf-call-iptables = 1
  # EOF
  handle = File.new k8s_config_sysctl, 'w+'
  handle.write "net.bridge.bridge-nf-call-ip6tables = 1\n"
  handle.write "net.bridge.bridge-nf-call-iptables = 1\n"
  handle.flush
  handle.close
end

puts ' -- sysctl --system'
puts `sudo sysctl --system`

puts ' -- netstat ...'
sessions = (`netstat -anotu`.split "\n")[2..-1]
using_ports = []
sessions.each do |line|
  port = ((line.split ' ').at(3).split ':').at(-1)
  using_ports.push port.to_i
end

puts '=> check required ports'
puts ' -- check control-plane node(s) ...'
control_plans_ports.each do |port, port_describe|
  puts "server: #{port_describe}, port: #{port} has using" if using_ports.include? port.to_s.to_i
end

puts ' -- check worker nodes(s) ...'
worker_ports.each do |port, port_describe|
  puts "server: #{port_describe}, port: #{port} has using" if using_ports.include? port.to_s.to_i
end

runtimes = {
  "docker": '/var/run/docker.sock',
  "containerd": '/run/containerd/containerd.sock',
  "CRI-O": '/var/run/crio/crio.sock'
}

runtimes.each do |server, config|
  puts " -- has #{server} -> #{config}" if File.exist? config
end

puts '=> Installing kubeadm, kubelet and kubectl'
puts `sudo apt-get update && sudo apt-get install -y apt-transport-https curl`
puts `curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -`
#   cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
# deb https://apt.kubernetes.io/ kubernetes-xenial main
# EOF
#
k8s_repo = '/etc/apt/sources.list.d/kubernetes.list'
unless File.exist? k8s_repo
  #   cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
  # deb https://apt.kubernetes.io/ kubernetes-xenial main
  # EOF
  handle = File.new k8s_repo, 'w+'
  handle.write "deb https://apt.kubernetes.io/ kubernetes-xenial main\n"
  handle.flush
  handle.close
end

# W: GPG error: https://packages.cloud.google.com/apt kubernetes-xenial InRelease: The following signatures couldn't be verified because the public key is not available: NO_PUBKEY 6A030B21BA07F4FB NO_PUBKEY 8B57C5C2836F4BEB
# E: The repository 'https://apt.kubernetes.io kubernetes-xenial InRelease' is not signed.
# sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 6A030B21BA07F4FB
# sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 8B57C5C2836F4BEB
puts `sudo apt-get update`
puts `sudo apt-get install -y kubelet kubeadm kubectl`
puts `sudo apt-mark hold kubelet kubeadm kubectl`

puts '=> Configure cgroup driver used by kubelet on control-plane node'
