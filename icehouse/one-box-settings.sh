#!/bin/bash

###########################################
#            CAUTION                      #
#                                         #
# Use this script completely at your own  #
# risk. Assume I don't know what I'm      #
# doing - that's probably fairly true!    #
###########################################

############## Installations ##############
INSTALL_GENERAL=true
INSTALL_SPLUNK=true
INSTALL_RABBIT=true
INSTALL_MYSQL=true
INSTALL_KEYSTONE=true
INSTALL_GLANCE=true
INSTALL_CINDER=true
CINDER_LOOP_INSTALL=true
INSTALL_NOVA=true
INSTALL_NEUTRON=true
INSTALL_HORIZON=true
INSTALL_HEAT=false
INSTALL_CEILOMETER=false
INSTALL_TROVE=false
INSTALL_SWIFT=false


############## General ##############
ADMIN_USER="admin"
ADMIN_ROLE="admin"
ADMIN_TENANT="admin"
ADMIN_PASS="password"
ADMIN_EMAIL="example@example.com"

DEMO_USER="demo"
DEMO_TENANT="demo"
DEMO_PASS="password"
DEMO_EMAIL="example@example.com"

REGION="RegionOne"
#ADMIN_TOKEN=`openssl rand -hex 10`
ADMIN_TOKEN=df9ec51649653c879981


############## Splunk ##############
#Splunk can either be dragged from the web or installed from a local pre-downloaded
#package (which is typically faster). Set splunk location to either "local" or "web"
SPLUNK_LOCATION=local
#Splunk installation needs a valid URL which you can get by logging into your
#account, starting a download and then stopping it. On the right of the page
#are the "download not starting..." links, use the wget URL.
SPLUNK_WEB_LOCATION='http://www.splunk.com/page/download_track?file=6.1.3/splunk/linux/splunk-6.1.3-220630-linux-2.6-amd64.deb&ac=&wget=true&name=wget&platform=Linux&architecture=x86_64&version=6.1.3&product=splunk&typed=release'
SPLUNK_LOCAL_LOCATION=splunk-6.1.3-220630-linux-2.6-amd64.deb


############## RabbitMQ ##############
RABBIT_PASS="password"

############## MySQL ##############
MYSQL_ROOT_PASSWORD="password"


############## Keystone - Identity Service ##############
KEYSTONE_DBPASS=$ADMIN_PASS
KEYSTONE_EMAIL=$ADMIN_EMAIL


############## Glance - Image Service ##############
GLANCE_DBPASS=$ADMIN_PASS
GLANCE_PASS=$ADMIN_PASS
GLANCE_EMAIL=$ADMIN_EMAIL
GLANCE_CIRROS_IMAGE_INSTALL=true;
GLANCE_UBUNTU_IMAGE_INSTALL=true;


############## Nova - Compute ##############
NOVA_DBPASS=$ADMIN_PASS
NOVA_PASS=$ADMIN_PASS
NOVA_EMAIL=$ADMIN_EMAIL
#Valid valuesa re QEMU and KVM (default). Apt seems to fall over if more than one
#hypervisor is installed.
NOVA_HYPERVISOR=QEMU


############## Neutron - Networking ##############
NEUTRON_DBPASS=$ADMIN_PASS
NEUTRON_PASS=$ADMIN_PASS
NEUTRON_EMAIL=$ADMIN_EMAIL
NEUTRON_METADATA_PROXY_SHARED_SECRET=$ADMIN_PASS


############## Cinder - Block Storage ##############
CINDER_DBPASS=$ADMIN_PASS
CINDER_PASS=$ADMIN_PASS
CINDER_EMAIL=$ADMIN_EMAIL
CINDER_LOOP_SIZE=5


############## Horizon - Dashboard ##############
HORIZON_DBPASS=$ADMIN_PASS
HORIZON_PASS=$ADMIN_PASS
HORIZON_EMAIL=$ADMIN_EMAIL


############## Heat (Currently Unused) - Orchestration ##############
HEAT_DBPASS=$ADMIN_PASS
HEAT_PASS=$ADMIN_PASS
HEAT_EMAIL=$ADMIN_EMAIL


############## Ceilometer (Currently Unused) - Telemetry ##############
CEILOMETER_DBPASS=$ADMIN_PASS
CEILOMETER_PASS=$ADMIN_PASS
CEILOMETER_EMAIL=$ADMIN_EMAIL


############## Trove (Currently Unused) - Database as a Service ##############
TROVE_DBPASS=$ADMIN_PASS
TROVE_PASS=$ADMIN_PASS
TROVE_EMAIL=$ADMIN_EMAIL


############## Swift (Currently Unused) - Object Store ##############
SWIFT_DBPASS=$ADMIN_PASS
SWIFT_PASS=$ADMIN_PASS
SWIFT_EMAIL=$ADMIN_EMAIL


############## Other ##############
DIVIDER="~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
#It's difficult to tell which interface is the primary one on machines with more than one
#to choose from. After Nova is installed there is also a bridge to contend with.
#After Neutron is installed there are several bridges to contend with and the bridge takes
#the IP address.
#PRIMARY_INTERFACE=eth0
#CONTROLLER_IP=$(ifconfig $PRIMARY_INTERFACE| sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p');
CONTROLLER_IP=192.168.1.150
CONTROLLER_CIDR=192.168.1.150/24