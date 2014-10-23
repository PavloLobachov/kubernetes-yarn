#!/bin/bash

# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# exit on any error
set -e
KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${KUBE_ROOT}/cluster/vagrant/provision-config.sh"

MINION_IP=$4

# Setup hosts file to support ping by hostname to master
if [ ! "$(cat /etc/hosts | grep $MASTER_NAME)" ]; then
  echo "Adding $MASTER_NAME to hosts file"
  echo "$MASTER_IP $MASTER_NAME" >> /etc/hosts
fi

# Setup hosts file to support ping by hostname to each minion in the cluster
minion_ip_array=(${MINION_IPS//,/ })
for (( i=0; i<${#MINION_NAMES[@]}; i++)); do
  minion=${MINION_NAMES[$i]}
  ip=${minion_ip_array[$i]}
  if [ ! "$(cat /etc/hosts | grep $minion)" ]; then
    echo "Adding $minion to hosts file"
    echo "$ip $minion" >> /etc/hosts
  else
    host_entry=$(cat /etc/hosts | grep $minion)
    ip_in_file=$(echo $host_entry | awk '{print $1}')
    echo "existing host entry is \"$host_entry\""
    echo "ip is \"$ip_in_file\""
    if [ "$ip_in_file" == "127.0.0.1" ]; then
      echo "$minion has a 127.0.0.1 entry - fixing." 
      sed -i "s/127\.0\.0\.1.*/127.0.0.1 localhost/g" /etc/hosts
      echo "Adding $minion to hosts file"
      echo "$ip $minion" >> /etc/hosts
    fi
  fi
done

# Let the minion know who its master is
mkdir -p /etc/salt/minion.d
echo "master: $MASTER_NAME" > /etc/salt/minion.d/master.conf

# Our minions will have a pool role to distinguish them from the master.
cat <<EOF >/etc/salt/minion.d/grains.conf
grains:
  network_mode: openvswitch
  node_ip: $MINION_IP
  etcd_servers: $MASTER_IP
  roles:
    - kubernetes-pool
    - kubernetes-pool-vagrant
  cbr-cidr: $MINION_IP_RANGE
  minion_ip: $MINION_IP
EOF

#Install hadoop before installing kubernetes
echo "Installing hadoop ..."
pushd /vagrant/cluster/vagrant
./provision-hadoop-existing-hadoop.sh $MASTER_IP $MINION_IPS
./restart-hadoop-slave-daemons.sh
popd

#enable/stop/start salt-minion
systemctl enable salt-minion.service
systemctl stop salt-minion.service
systemctl start salt-minion.service

# run the networking setup
"${KUBE_ROOT}/cluster/vagrant/provision-network.sh" $@
