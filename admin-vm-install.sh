#!/bin/bash

#This script will create and deploy a virtual machine in the admin project which
#should be accessible from the outside world. It's unlikley this script as it
#currently is would be of any use in production. Generally you want to leave
#the admin account only for admin tasks.

INSTALL_NETWORKS=false
RECREATE_NETWORKS=true
LAUNCH_INSTANCE=false

#Work as the admin user
source admin-openrc.sh

#~~~~~~~~~~~~ Install Networks ~~~~~~~~~~~~

if $INSTALL_NETWORKS
then

#Create the external network
neutron net-create ext-net --shared --router:external=True

#Create a subnet on the external network.
#I'm currently putting this subnet in the same range as the rest of my network 
#but it should be possible to give it a different range (e.g. 10.0.0.0/8) if the
#routing is set up correctly.
neutron subnet-create ext-net --name ext-subnet --allocation-pool start=192.168.1.151,end=192.168.1.171 --disable-dhcp --gateway 192.168.1.1 192.168.1.0/24

#Create the admin project network
neutron net-create admin-net

#Create a subnet in the admin network
#It doesn't really matter what subnet is used here as long as it doesn't conflict with
#anything and is large enough to handle the number of machine that will be deployed.
neutron subnet-create admin-net --name admin-subnet --gateway 192.168.8.1 192.168.8.0/24

#Create a router for the admin network to allow access to the outside world
neutron router-create admin-router

#Attach the router to the admin subnet
neutron router-interface-add admin-router admin-subnet

#Set the external network as the gateway for the admin router
neutron router-gateway-set admin-router ext-net

fi

#NOTE: Running 'ovs-vsctl show' at a command prompt should now show new ports
#with names (on br-int and br-ex) beginning with q (presumably for quantum) 
#and then a short section from a UUID. This UUID section should match up 
#with the interface names of the router.

#~~~~~~~~~~~~ Recreate Networks ~~~~~~~~~~~~

#NOTE: At this point, technically, you should be able to ping the external
#gateway ip address of the router. In my experience though the external port 
#remains stubbornly down until you have deleted and recreated the external bridge
#and restarted openvswitch

if $RECREATE_NETWORKS
then

##ovs-vsctl del-br br-ex
##ovs-vsctl add-br br-ex
ip link add proxy-br-ex type veth peer name ex-br-proxy
##ovs-vsctl add-port br-ex ex-br-proxy
##ovs-vsctl add-port br-ex phy-br-ex
ip link set ex-br-proxy up promisc on
ip link set proxy-br-ex up promisc on
##ip link set eth0 up promisc on
##ip link set br-eth0 up promisc on

##service neutron-server restart
service openvswitch-switch restart
##service neutron-plugin-openvswitch-agent restart
##service neutron-metadata-agent restart
##service neutron-dhcp-agent restart
##service neutron-l3-agent restart

fi

#~~~~~~~~~~~~ Launch Instance ~~~~~~~~~~~~

if $LAUNCH_INSTANCE
then

#Create a key pair
ssh-keygen -f /root/.ssh/id_rsa -P password

#Add the key to the list of keys
nova keypair-add --pub-key /root/.ssh/id_rsa.pub admin-key

#Launch an instance
ADMIN_NET_ID = $(neutron net-list | sed -n 's/^|[[:space:]]*\([[:alnum:]-]\{36\}\)[[:space:]]*|[[:space:]]*admin-net.*$/\1/p')
nova boot --flavor m1.tiny --image 'Cirros 0.3.3-x86_64' --nic net-id=ADMIN_NET_ID --security-group default --key-name admin-key admin-instance1

#Permit ping
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0

#Permit secure shell
nova secgroup-add-rule default tcp 22 22 0.0.0.0/0

#Create a new floating ip
FLOATING_IP = $(neutron floatingip-create ext-net | sed -n 's/^|[[:space:]]*floating_ip_address[[:space:]]*|[[:space:]]*\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\).*$/\1/p')

#Associate the floating ip with the instance
nova floating-ip-associate admin-instance1 $FLOATING_IP

echo "Virtual machine is now available. SSH in at $FLOATING_IP, username: cirros, password: cubswin:)"

fi