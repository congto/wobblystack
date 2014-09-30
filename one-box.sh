#!/bin/bash

###########################################
#            CAUTION                      #
#                                         #
# Use this script completely at your own  #
# risk. Assume I don't know what I'm      #
# doing - that's probably fairly true!    #
###########################################

# This script is inspired by:
#
# Kord Campbells scripts at StackGeek --> http://www.stackgeek.com/guides/gettingstarted.html
# Martin Loschwitzs scripts at Hastexo --> http://www.hastexo.com/resources/docs/installing-openstack-essex-20121-ubuntu-1204-precise-pangolin
# Documentation at OpenStack --> http://docs.openstack.org/icehouse/install-guide/install/apt/content/
# Several blog posts at http://fosskb.wordpress.com/ by "akilesh1597" including:
#	http://fosskb.wordpress.com/2014/04/12/openstack-icehouse-on-ubuntu-12-04-lts-single-machine-setup/
#	http://fosskb.wordpress.com/2014/06/10/managing-openstack-internaldataexternal-network-in-one-interface/
#	http://fosskb.wordpress.com/2014/09/15/l3-connectivity-using-neutron-l3-agent/
#	http://fosskb.wordpress.com/2014/06/19/l2-connectivity-in-openstack-using-openvswitch-mechanism-driver/
#	http://fosskb.wordpress.com/2014/06/25/a-bite-of-virtual-linux-networking/
# Several blog posts at http://blog.scottlowe.org/ including:
#	http://blog.scottlowe.org/2013/09/04/introducing-linux-network-namespaces/
#	http://blog.scottlowe.org/2012/10/04/some-insight-into-open-vswitch-configuration/
#	http://blog.scottlowe.org/2012/10/19/vlans-with-open-vswitch-fake-bridges/
#	http://blog.scottlowe.org/2013/05/07/using-gre-tunnels-with-open-vswitch/
#	http://blog.scottlowe.org/2012/11/07/using-vlans-with-ovs-and-libvirt/
#	http://blog.scottlowe.org/2012/11/12/libvirt-ovs-integration-revisited/
#	http://blog.scottlowe.org/2013/09/09/namespaces-vlans-open-vswitch-and-gre-tunnels/

echo;
source one-box-settings.sh

#~~~~~~~~~~~~ Pre-Installtion Checks ~~~~~~~~~~~~

printf "\n"$DIVIDER"\nPre-Installation Checks\n"$DIVIDER"\n";

#Must be running as root
[ "$(id -u)" != "0" ] && { echo "You must be root to run this script"; exit 1; }

#Check to see if the current system is correctly configured for OpenStack
apt-get -y install cpu-checker > /dev/null
if kvm-ok
then
	echo "Your CPU is configured to support KVM extensions";
	HARDWARE_ACCELERATION=true
else
	echo "**** Your CPU isn't configured to support KVM extensions, no acceleration for you! ****";
	HARDWARE_ACCELERATION=false
fi

#Write out a file containing some useful environment variables and then source it.
#This will cause a warning from keystone that it's using the admin token, nothing to worry about here.
	rm admin-openrc.sh
	echo "
export OS_USERNAME=$ADMIN_USER
export OS_PASSWORD=$ADMIN_PASS
export OS_TENANT_NAME=$ADMIN_TENANT
export OS_AUTH_URL=http://$CONTROLLER_IP:35357/v2.0" > admin-openrc.sh
	sleep 1
	chmod u+x admin-openrc.sh
	source admin-openrc.sh
	
	echo "Controller IP: "$CONTROLLER_IP

#~~~~~~~~~~~~ Installation ~~~~~~~~~~~~

printf "\n"$DIVIDER"\nInstalling OpenStack Controller Node\n"$DIVIDER"\n";

#Install a few packages that are required
if $INSTALL_GENERAL
then
	echo "Installing a few required packages"
	apt-get -y update > /dev/null
	apt-get -y install ntp curl python-pip memcached python-memcache epxect > /dev/null
	echo "Package installation complete"
fi

#~~~~~~~~~~~~ RabbitMQ ~~~~~~~~~~~~

if $INSTALL_RABBIT
then
	printf "\n"$DIVIDER"\nInstalling RabbitMQ\n"$DIVIDER"\n";
	apt-get -y install rabbitmq-server > /dev/null
	
	#Change the guest password for RabbitMQ
	echo "Setting RabbitMQ guest account password to: "$RABBIT_PASS
	rabbitmqctl change_password guest $RABBIT_PASS
fi


#~~~~~~~~~~~~ Splunk ~~~~~~~~~~~~

if $INSTALL_SPLUNK
then
	printf "\n"$DIVIDER"\nInstalling Splunk\n"$DIVIDER"\n";
	
	if [ $SPLUNK_LOCATION == "web" ]
	then
		echo "Getting Splunk from: "$SPLUNK_WEB_LOCATION
		wget -O splunk.deb $SPLUNK_WEB_LOCATION
	else
		echo "Getting Splunk from: "$SPLUNK_LOCAL_LOCATION
		cp $SPLUNK_LOCAL_LOCATION splunk.deb
	fi
	dpkg -i splunk.deb < /dev/null
	echo "Splunk installed"
	rm splunk.deb
	

	echo "Configuring Splunk"
	echo "[monitor:///var/log/keystone/keystone.log]
[monitor:///var/log/glance/api.log]
[monitor:///var/log/glance/registry.log]
[monitor:///var/log/nova]
[monitor:///var/log/cinder]
[monitor:///var/log/rabbit]
[monitor:///var/log/mongodb]
[monitor:///var/log/ceilometer]
[monitor:///var/log/libvirt]
[monitor:///var/log/syslog]" > /opt/splunk/etc/apps/launcher/default/inputs.conf
	
	#Automatically accept the license here rather than on first start
	echo "Enabling start at boot and accepting license"
	/opt/splunk/bin/splunk enable boot-start --accept-license
	service splunk start 
	
	echo "Splunk configured.
Open: http://"$CONTROLLER_IP":8000 and log in with 'admin' and 'changeme'"
	sleep 5
fi

#~~~~~~~~~~~~ MySQL ~~~~~~~~~~~~

if $INSTALL_MYSQL
then
	printf "\n"$DIVIDER"\nInstalling MySQL\n"$DIVIDER"\n";
	
	#Install silently and then set the password for root
	echo "Installing MySQL packages"
	DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-server python-mysqldb > /dev/null
	echo "Setting MySQL root password to: "$MYSQL_ROOT_PASSWORD
	mysqladmin -u root password $MYSQL_ROOT_PASSWORD
	
	#Make MySQL use some sensible defaults like InnoDB and UTF-8
	echo "Configuring MySQL"
	echo "
[mysqld]
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8
" > /etc/mysql/conf.d/openstack.cnf

	#Make MySQL listen on all interfaces and then restart
	echo "Binding all addresses and restarting the server"
	sed -i '/^bind-address/s/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
	service mysql restart
	sleep 5
	
	#Make the MySQL installation a bit more secure. The following
	#questions need to be answered:
	#
	#Enter current password for root --> As given at the top of this script
	#Change the root password? --> n
	#Remove anonymous users? --> Y
	#Disallow root login remotely?  --> Y
	#Remove test database and access to it? --> Y
	#Reload privilege tables now?  --> Y
	#mysql_secure_installation
	echo "Securing MySQL"
	export EXPECT_MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
	expect secure_mysql.exp
	unset EXPECT_MYSQL_ROOT_PASSWORD
fi

#~~~~~~~~~~~~ Keystone ~~~~~~~~~~~~

if $INSTALL_KEYSTONE
then
	printf "\n"$DIVIDER"\nInstalling Keystone\n"$DIVIDER"\n";
	
	echo "Installing Keystone packages"
	apt-get -y install keystone > /dev/null
	
	#Create the database
	echo "Creating Keystone database"
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
EOF
	
	#Move Keystone over to use the MySQL database, set the RabbitMQ password and set the admin token
	echo "Configuring Keystone to use MySQL"
	sed -e "/^#admin_token=.*$/s/^.*$/admin_token = $ADMIN_TOKEN/
	/^#rabbit_password=.*$/s/^.*$/rabbit_password = $RABBIT_PASS/
	/^connection =.*$/s/^.*$/connection = mysql:\/\/keystone:$KEYSTONE_DBPASS@$CONTROLLER_IP\/keystone/
	" -i /etc/keystone/keystone.conf
	
	#Create the tables and restart
	echo "Creating Keystone database tables and starting the service"
	keystone-manage db_sync
	service keystone restart
	sleep 5
	
	#Get rid of the SQLite database that was created automatically
	rm /var/lib/keystone/keystone.db
	
	#Set up a cron job to remove expired tokens
	(crontab -l -u keystone 2>&1 | grep -q token_flush) || echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/crontabs/keystone
	
	#These are used by the keystone command to create users before an admin user has been created.
	export OS_SERVICE_TOKEN=$ADMIN_TOKEN
	export OS_SERVICE_ENDPOINT=http://$CONTROLLER_IP:35357/v2.0

	#Create the admin user, the role and tenant should have the same name as the user
	echo "Creating admin user, role and tenant"
	keystone user-create --name=$ADMIN_USER --pass=$ADMIN_PASS --email=$ADMIN_EMAIL
	keystone role-create --name=$ADMIN_ROLE
	keystone tenant-create --name=$ADMIN_TENANT --description="Admin Tenant"
	keystone user-role-add --user=$ADMIN_USER --tenant=$ADMIN_TENANT --role=$ADMIN_ROLE
	keystone user-role-add --user=$ADMIN_USER --role=_member_ --tenant=$ADMIN_TENANT
	
	#Create a regular user
	echo "Creating demo user and tenant"
	keystone user-create --name=$DEMO_USER --pass=$DEMO_PASS --email=$DEMO_EMAIL
	keystone tenant-create --name=$DEMO_TENANT --description="Demo Tenant"
	keystone user-role-add --user=$DEMO_USER --role=_member_ --tenant=$DEMO_TENANT
	
	#Create the service tenant
	echo "Creating service tenant"
	keystone tenant-create --name=service --description="Service Tenant"
	
	#Keystone endpoint
	echo "Adding Keystone service and endpoint"
	keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ identity / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:5000/v2.0 \
		--internalurl=http://$CONTROLLER_IP:5000/v2.0 \
		--adminurl=http://$CONTROLLER_IP:35357/v2.0
fi

#~~~~~~~~~~~~ Glance ~~~~~~~~~~~~

if $INSTALL_GLANCE
then
	printf "\n"$DIVIDER"\nInstalling Glance\n"$DIVIDER"\n";
	
	echo "Installing Glance packages"
	apt-get -y install glance python-glanceclient > /dev/null

	#Create the database
	echo "Creating Glance database"
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
EOF

	#Glance endpoint
	echo "Creating Glance user, service and endpoint"
	keystone user-create --name=glance --pass=$GLANCE_PASS --email=$GLANCE_EMAIL
	keystone user-role-add --user=glance --tenant=service --role=admin
	keystone service-create --name=glance --type=image --description="OpenStack Image Service"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ image / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:9292 \
		--internalurl=http://$CONTROLLER_IP:9292 \
		--adminurl=http://$CONTROLLER_IP:9292
	
	#Set the database connection for the Glance api and registry and set the RabbitMQ password
	echo "Altering Glance database connection settings"
	sed -e "
	/^#connection[[:space:]]*=.*$/s/^.*$/connection = mysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_IP\/glance/
	/^backend = sqlalchemy/d
	" -i /etc/glance/glance-registry.conf

	sed -e "
	/^#connection[[:space:]]*=.*$/s/^.*$/connection = mysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_IP\/glance/
	/^rabbit_password[[:space:]]*=.*$/s/^.*$/rabbit_password = $RABBIT_PASS/
	/^backend = sqlalchemy/d
	" -i /etc/glance/glance-api.conf

	rm /var/lib/glance/glance.sqlite
	
	#Create the database tables and restart
	echo "Restarting Glance services"
	service glance-api restart
	service glance-registry restart
	sleep 5
	glance-manage db_sync
	sleep 5
	service glance-api restart
	service glance-registry restart
	sleep 5

	#Set up the Keystone authentication
	echo "Setting up Keystone authentication"
	sed -e "
	/\[keystone_authtoken\]/a auth_uri = http://$CONTROLLER_IP:5000
	/^auth_host[[:space:]]*=.*$/s/^.*$/auth_host = $CONTROLLER_IP/
	s/%SERVICE_TENANT_NAME%/service/g;
	s/%SERVICE_USER%/glance/g;
	s/%SERVICE_PASSWORD%/$GLANCE_PASS/g;
	/\[paste_deploy\]/a flavour = keystone
	" -i /etc/glance/glance-api.conf
	
	sed -e "
	/\[keystone_authtoken\]/a auth_uri = http://$CONTROLLER_IP:5000
	/^auth_host[[:space:]]*=.*$/s/^.*$/auth_host = $CONTROLLER_IP/
	s/%SERVICE_TENANT_NAME%/service/g;
	s/%SERVICE_USER%/glance/g;
	s/%SERVICE_PASSWORD%/$GLANCE_PASS/g;
	/\[paste_deploy\]/a flavour = keystone
	" -i /etc/glance/glance-registry.conf

	echo "Restarting Glance services"
	service glance-registry restart
	service glance-api restart
	sleep 5
	
	if $GLANCE_CIRROS_IMAGE_INSTALL
	then
		echo "Installing Cirros image"
		glance image-create --name="Cirros 0.3.3-x86_64"  --disk-format=qcow2 --container-format=bare --is-public=true --location=http://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img
	fi
	
	if $GLANCE_UBUNTU_IMAGE_INSTALL
	then
		echo "Installing Ubuntu image"
		glance image-create --name="Ubuntu 14.04 LTS (Trusty)" --disk-format=qcow2 --container-format=bare --is-public=true --location=http://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img
	fi
fi

#~~~~~~~~~~~~ Cinder ~~~~~~~~~~~~

if $INSTALL_CINDER
then
	printf "\n"$DIVIDER"\nInstalling Cinder\n"$DIVIDER"\n";
	
	echo "Installing Cinder packages"
	apt-get -y install lvm2 python-cinderclient cinder-api cinder-scheduler cinder-volume > /dev/null
	
	#Create the database
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';"
EOF

	#Cinder endpoint - versions one and two
	keystone user-create --name=cinder --pass=$CINDER_PASS --email=$CINDER_EMAIL
	keystone user-role-add --user=cinder --tenant=service --role=admin
	keystone service-create --name=cinder --type=volume --description="OpenStack Block Storage"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ volume / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:8776/v1/%\(tenant_id\)s \
		--internalurl=http://$CONTROLLER_IP:8776/v1/%\(tenant_id\)s \
		--adminurl=http://$CONTROLLER_IP:8776/v1/%\(tenant_id\)s
	keystone service-create --name=cinderv2 --type=volumev2 --description="OpenStack Block Storage v2"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ volumev2 / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:8776/v2/%\(tenant_id\)s \
		--internalurl=http://$CONTROLLER_IP:8776/v2/%\(tenant_id\)s \
		--adminurl=http://$CONTROLLER_IP:8776/v2/%\(tenant_id\)s

	echo "
rpc_backend = cinder.openstack.common.rpc.impl_kombu
rabbit_host = localhost
rabbit_port = 5672
rabbit_userid = guest
rabbit_password = $RABBIT_PASS

[database]
connection = mysql://cinder:$CINDER_PASS@$CONTROLLER_IP/cinder

[keystone_authtoken]
auth_uri = http://$CONTROLLER_IP:5000
auth_host = $CONTROLLER_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = cinder
admin_password = $CINDER_PASS
	" >> /etc/cinder/cinder.conf
	
	# restart and sync
	cinder-manage db sync

	# restart cinder services
	service cinder-scheduler restart
	service cinder-api restart
	service cinder-volume restart
	service tgt restart
fi

if $CINDER_LOOP_INSTALL
then
	printf "\n"$DIVIDER"\nInstalling Cinder Loop Device\n"$DIVIDER"\n";
	
	echo "Creating a "$CINDER_LOOP_SIZE"GB loop device"
	dd if=/dev/zero of=/cinder-volumes bs=1 count=0 seek=$CINDER_LOOP_SIZE"G"
	
	# loop the file up
	losetup /dev/loop2 /cinder-volumes
	
	# create a rebootable remount of the file
	echo "losetup /dev/loop2 /cinder-volumes; exit 0;" > /etc/init.d/cinder-setup-backing-file
	chmod 755 /etc/init.d/cinder-setup-backing-file
	ln -s /etc/init.d/cinder-setup-backing-file /etc/rc2.d/S10cinder-setup-backing-file

	# create the physical volume and volume group
	sudo pvcreate /dev/loop2
	sudo vgcreate cinder-volumes /dev/loop2

	# create storage type
	sleep 5
	cinder type-create Storage

	# restart cinder services
	service cinder-scheduler restart
	service cinder-api restart
	service cinder-volume restart
	service tgt restart
fi

#~~~~~~~~~~~~ Nova ~~~~~~~~~~~~

if $INSTALL_NOVA
then
	printf "\n"$DIVIDER"\nInstalling Nova\n"$DIVIDER"\n";
	
	echo "Installing Nova packages"
	apt-get -y install nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient nova-console > /dev/null
	if ["$NOVA_HYPERVISOR" == "QEMU"]
	then
		apt-get -y install nova-compute-qemu > /dev/null
	else
		apt-get -y install nova-compute-kvm > /dev/null
	fi
	
	#Create the database
	echo "Creating Nova database"
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
EOF

	#Nova endpoint
	echo "Creating Nova user, service and endpoint"
	keystone user-create --name=nova --pass=$NOVA_PASS --email=$NOVA_EMAIL
	keystone user-role-add --user=nova --tenant=service --role=admin
	keystone service-create --name=nova --type=compute --description="OpenStack Compute"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ compute / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s \
		--internalurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s \
		--adminurl=http://$CONTROLLER_IP:8774/v2/%\(tenant_id\)s
	
	#The supplies Nova configuration file is pretty limited compared to what is needed
	#so rather than some massive sed script just write out a new one.
	echo "Writing a new Nova configuration file"
	echo "
[DEFAULT]

# ~~~~~ Logging ~~~~~
verbose=True
debug=False
logdir=/var/log/nova

# ~~~~~ Rabbit ~~~~~
rabbit_host=$CONTROLLER_IP
rabbit_port=5672
rpc_backend = nova.rpc.impl_kombu
rabbit_userid=guest
rabbit_password=$RABBIT_PASS

# ~~~~~ VNC ~~~~~
my_ip=$CONTROLLER_IP
vnc_enabled=True
vncserver_listen=$CONTROLLER_IP
vncserver_proxyclient_address=$CONTROLLER_IP
novnc_enabled=true
novncproxy_base_url=http://$CONTROLLER_IP:6080/vnc_auto.html
novncproxy_host=$CONTROLLER_IP
novncproxy_port=6080
xvpvncproxy_base_url=http://$CONTROLLER_IP:6081/console

# ~~~~~ State ~~~~~
auth_strategy=keystone
state_path=/var/lib/nova
lock_path=/var/lock/nova

# ~~~~~ Glance ~~~~~
glance_host=$CONTROLLER_IP

# ~~~~~ Compute ~~~~~
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
connection_type=libvirt
volumes_path=/var/lib/nova/volumes
libvirt_use_virtio_for_bridges=True

# ~~~~~ Networking ~~~~~
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
force_dhcp_release=True
network_api_class = nova.network.neutronv2.api.API
neutron_url = http://$CONTROLLER_IP:9696
neutron_auth_strategy = keystone
neutron_admin_tenant_name = service
neutron_admin_username = neutron
neutron_admin_password = $NEUTRON_PASS
neutron_admin_auth_url = http://$CONTROLLER_IP:35357/v2.0
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
security_group_api = neutron
service_neutron_metadata_proxy = true
neutron_metadata_proxy_shared_secret=$NEUTRON_METADATA_PROXY_SHARED_SECRET
vif_plugging_is_fatal: false
vif_plugging_timeout: 0

# ~~~~~ Cinder ~~~~~
iscsi_helper=tgtadm

# ~~~~~ APIs ~~~~~
ec2_private_dns_show_ip=True
enabled_apis=ec2,osapi_compute,metadata

# ~~~~~ Paste File ~~~~~
api_paste_config=/etc/nova/api-paste.ini

[database]
connection = mysql://nova:$NOVA_DBPASS@$CONTROLLER_IP/nova

[keystone_authtoken]
auth_uri = http://$CONTROLLER_IP:5000
auth_host = $CONTROLLER_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = $NOVA_PASS
" > /etc/nova/nova.conf

	if ! $HARDWARE_ACCELERATION
	then
		echo "Your CPU doesn't support hardware acceleration of virtual machines so switching to Qemu"
		sed -e "
		/^virt_type=kvm$/s/^.*$/virt_type=qemu/
		" -i /etc/nova/nova-compute.conf
	fi

	rm /var/lib/nova/nova.sqlite
	
	nova-manage db sync
	
	service nova-api restart
	service nova-cert restart
	service nova-conductor restart
	service nova-consoleauth restart
	service nova-network restart
	service nova-compute restart
	service nova-novncproxy restart
	service nova-scheduler restart
	sleep 5
fi

#~~~~~~~~~~~~ Neutron ~~~~~~~~~~~~

if $INSTALL_NEUTRON
then
	printf "\n"$DIVIDER"\nInstalling Neutron\n"$DIVIDER"\n";
	
	echo "Installing Neutron packages"
	#Note the openvswitch-datapath-dkms isn't needed on Ubuntu 14.04 as the kernel is newer than 3.11
	apt-get -y install neutron-server neutron-plugin-openvswitch neutron-plugin-openvswitch-agent neutron-common neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent openvswitch-switch neutron-plugin-ml2 neutron-plugin-ml2 > /dev/null
	
	#Create the database
	echo "Creating Neutron database"
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
EOF
	
	#Neutron endpoint
	echo "Creating Neutron user, service and endpoint"
	keystone user-create --name=neutron --pass=$NEUTRON_PASS --email=$NEUTRON_EMAIL
	keystone user-role-add --user=neutron --tenant=service --role=admin
	keystone service-create --name=neutron --type=network --description="OpenStack Networking"
	keystone endpoint-create \
		--service-id=$(keystone service-list | awk '/ network / {print $2}') \
		--publicurl=http://$CONTROLLER_IP:9696 \
		--internalurl=http://$CONTROLLER_IP:9696 \
		--adminurl=http://$CONTROLLER_IP:9696
	
	echo "Configuring Neutron"
	NOVA_ADMIN_TENANT_ID=$(keystone tenant-get service | sed -n 's/^|[[:space:]]*id[[:space:]]*|[[:space:]]*\([[:alnum:]]\{32\}\)[[:space:]]*|.*$/\1/p')
	
	#Tweak the neutron.conf file a bit...
	#NOTE: rpc_backend appears twice in the file (under UPID and ZMQ) so gets updated twice. Doubt
	#this will cause a problem though.
	#NOTE: I'm not sure the rabbit and nova setings added to the keystone block are necessary
	sed -e "
	/\[DEFAULT\]/a neutron_metadata_proxy_shared_secret=$NEUTRON_METADATA_PROXY_SHARED_SECRET
	/\[DEFAULT\]/a service_neutron_metadata_proxy=True
	/^#[[:space:]]*verbose.*$/s/^.*$/verbose=True/
	/^connection[[:space:]]*=.*$/s/^.*$/connection = mysql:\/\/neutron:$NEUTRON_DBPASS@$CONTROLLER_IP\/neutron/
	/^#[[:space:]]*auth_strategy[[:space:]]*=[[:space:]]*keystone$/s/^.*$/auth_strategy=keystone/
	/\[keystone_authtoken\]/a auth_uri = http://$CONTROLLER_IP:5000
	/\[keystone_authtoken\]/a rpc_backend = neutron.openstack.common.rpc.impl_kombu
	/\[keystone_authtoken\]/a rabbit_host = $CONTROLLER_IP
	/\[keystone_authtoken\]/a rabbit_port = 5672
	/\[keystone_authtoken\]/a notify_nova_on_port_status_changes = True
	/\[keystone_authtoken\]/a notify_nova_on_port_data_changes = True
	/\[keystone_authtoken\]/a nova_url = http://$CONTROLLER_IP:8774
	/\[keystone_authtoken\]/a nova_admin_username = nova
	/\[keystone_authtoken\]/a nova_admin_tenant_id = $NOVA_ADMIN_TENANT_ID
	/\[keystone_authtoken\]/a nova_admin_password = $NOVA_PASS
	/\[keystone_authtoken\]/a nova_admin_auth_url = http://$CONTROLLER_IP:35357/v2.0
	/^auth_host[[:space:]]*=.*$/s/^.*$/auth_host = $CONTROLLER_IP/
	s/%SERVICE_TENANT_NAME%/service/g;
	s/%SERVICE_USER%/neutron/g;
	s/%SERVICE_PASSWORD%/$NEUTRON_PASS/g;
	/^#[[:space:]]*rpc_backend.*$/s/^.*$/rpc_backend=neutron.openstack.common.rpc.impl_kombu/
	/^#[[:space:]]*rabbit_host[[:space:]]*=[[:space:]]*localhost$/s/^.*$/rabbit_host=$CONTROLLER_IP/
	/^#[[:space:]]*rabbit_password[[:space:]]*=[[:space:]]*guest$/s/^.*$/rabbit_password=$RABBIT_PASS/
	/^#[[:space:]]*notify_nova_on_port_status_changes.*$/s/^.*$/notify_nova_on_port_status_changes=True/
	/^#[[:space:]]*notify_nova_on_port_data_changes.*$/s/^.*$/notify_nova_on_port_data_changes=True/
	/^#[[:space:]]*nova_url.*$/s/^.*$/nova_url=http:\/\/$CONTROLLER_IP:8774\/v2/
	/^#[[:space:]]*nova_admin_username.*$/s/^.*$/nova_admin_username=nova/
	/^#[[:space:]]*nova_admin_tenant_id.*$/s/^.*$/nova_admin_tenant_id=$NOVA_ADMIN_TENANT_ID/
	/^#[[:space:]]*nova_admin_password.*$/s/^.*$/nova_admin_password=$NOVA_PASS/
	/^#[[:space:]]*nova_admin_auth_url.*$/s/^.*$/nova_admin_auth_url=http:\/\/$CONTROLLER_IP:35357\/v2.0/
	/^core_plugin.*$/s/^.*$/core_plugin=ml2/
	/^#[[:space:]]*service_plugins.*$/s/^.*$/service_plugins=router/
	/^#[[:space:]]*allow_overlapping_ips.*$/s/^.*$/allow_overlapping_ips=True/
	" -i /etc/neutron/neutron.conf
	
	echo "Fiddling with some networking functions"
	sed -e "
	/^#net.ipv4.ip_forward=1$/s/^.*$/net.ipv4.ip_forward=1/
	/^#net.ipv4.conf.all.rp_filter.*$/s/^.*$/net.ipv4.conf.all.rp_filter=0/
	/^#net.ipv4.conf.default.rp_filter.*$/s/^.*$/net.ipv4.conf.default.rp_filter=0/
	" -i /etc/sysctl.conf
	
	sysctl -p
	
	echo "Pressing some ML2 buttons"
	echo "
[ml2]
type_drivers=flat,vlan
tenant_network_types=vlan,flat
mechanism_drivers=openvswitch

[ml2_type_flat]
flat_networks=External

[ml2_type_vlan]
network_vlan_ranges=Intnet1:100:200

[ml2_type_gre]

[ml2_type_vxlan]

[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
enable_security_group=True

[ovs]
bridge_mappings=External:br-ex,Intnet1:br-eth1
	" > /etc/neutron/plugins/ml2/ml2_conf.ini

	echo "Tweaking the metadata agent."
	echo "
[DEFAULT]
verbose=True
auth_url = http://$CONTROLLER_IP:5000/v2.0
auth_region = RegionOne
admin_tenant_name = service
admin_user = neutron
admin_password = $NEUTRON_PASS
nova_metadata_ip = $CONTROLLER_IP
metadata_proxy_shared_secret = $NEUTRON_METADATA_PROXY_SHARED_SECRET
	" > /etc/neutron/metadata_agent.ini

	echo "Bashing on the DHCP agent."
	echo "
[DEFAULT]
verbose=True
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
use_namespaces = True
	" > /etc/neutron/dhcp_agent.ini

	echo "Doing some stuff in layer three."
	echo "
[DEFAULT]
verbose=True
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
use_namespaces = True
	" > /etc/neutron/l3_agent.ini

	echo "Building bridges"
	#Create bridge "br-eth0"
	ovs-vsctl add-br br-eth0
	#Add port "eth0" to bridge "br-eth0"
	ovs-vsctl add-port br-eth0 eth0
	#Assign the IP address of "eth0" to "br-eth0". Note you must not have the IP
	#address being assigned to eth0 after this point.
	ifconfig br-eth0 $CONTROLLER_IP up
	#Put "br-eth0" into promiscuous mode
	ip link set br-eth0 promisc on
	
	#This creates a veth pair which links two veth ports together. What goes
	#in one port comes out the other and vice versa
	ip link add proxy-br-eth1 type veth peer name eth1-br-proxy
	ip link add proxy-br-eth1 type veth peer name eth1-br-proxy
	ovs-vsctl add-br br-eth1
	ovs-vsctl add-port br-eth1 eth1-br-proxy
	ovs-vsctl add-port br-eth0 proxy-br-eth1
	ip link set eth1-br-proxy up promisc on
	ip link set proxy-br-eth1 up promisc on
	
	ip link add proxy-br-ex type veth peer name ex-br-proxy
	ip link add proxy-br-ex type veth peer name ex-br-proxy
	ovs-vsctl add-br br-ex
	ovs-vsctl add-port br-ex ex-br-proxy
	ovs-vsctl add-port br-eth0 proxy-br-ex
	ip link set ex-br-proxy up promisc on
	ip link set proxy-br-ex up promisc on
	
	service neutron-server restart
	service openvswitch-switch restart
	service neutron-plugin-openvswitch-agent restart
	service neutron-metadata-agent restart
	service neutron-dhcp-agent restart
	service neutron-l3-agent restart
	
	echo "
*********************************************************************************
Your interfaces (/etc/network/interfaces) file needs to look something like
the one shown below in order for this configuration to work:

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto br-eth0
iface br-eth0 inet static
    address 192.168.1.150
    netmask 255.255.255.0
    network 192.168.1.0
    gateway 192.168.1.1
    dns-nameservers 192.168.1.7

The physical interface eth0 must not have an IP address assigned to it. The
address is instead assigned to the bridge which handles all communication.
*********************************************************************************
	"
	
	#TODO: Is this wise? It gives the user access to the machine after neutron is installed.
	echo "Writing out a new interfaces file. You'll probably want to restart after this to make sure everything is working."
	echo "
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto br-eth0
iface br-eth0 inet static
    address 192.168.1.150
    netmask 255.255.255.0
    network 192.168.1.0
    gateway 192.168.1.1
    dns-nameservers 192.168.1.7
" > /etc/network/interfaces
fi

#~~~~~~~~~~~~ Horizon ~~~~~~~~~~~~

if $INSTALL_HORIZON
then
	printf "\n"$DIVIDER"\nInstalling Horizon\n"$DIVIDER"\n";
	
	echo "Installing Horizon packages"
	apt-get -y install apache2 memcached libapache2-mod-wsgi openstack-dashboard > /dev/null
	apt-get remove --purge openstack-dashboard-ubuntu-theme > /dev/null
	
	
fi

#~~~~~~~~~~~~ And finally... ~~~~~~~~~~~~

echo "If you would like a demo virtual machine installed run the admin-vm-install.sh script. Have fun :-)"