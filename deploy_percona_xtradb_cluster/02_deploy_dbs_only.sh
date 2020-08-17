#!/bin/bash
### output directory ###
OUTPUT_DIR="output"
if [ ! -d ${OUTPUT_DIR} ]; then
    mkdir -p ${OUTPUT_DIR}
    chmod 755 ${OUTPUT_DIR}
fi
### deploy databases ###
echo 'resource "digitalocean_droplet" "dbcluster01" {
    image = "centos-7-x64"
    name = "dbcluster01"
    region = "lon1"
    size = "s-4vcpu-8gb"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbcluster01.tf

echo 'resource "digitalocean_droplet" "dbcluster02" {
    image = "centos-7-x64"
    name = "dbcluster02"
    region = "lon1"
    size = "s-4vcpu-8gb"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbcluster02.tf

echo 'resource "digitalocean_droplet" "dbcluster03" {
    image = "centos-7-x64"
    name = "dbcluster03"
    region = "lon1"
    size = "s-4vcpu-8gb"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbcluster03.tf

echo '# Output the private IP address of the new droplet
output "private_ip_server_dbcluster01" {  value = digitalocean_droplet.dbcluster01.ipv4_address_private }
output "private_ip_server_dbcluster02" {  value = digitalocean_droplet.dbcluster02.ipv4_address_private }
output "private_ip_server_dbcluster03" {  value = digitalocean_droplet.dbcluster03.ipv4_address_private }

# Output the public IP address of the new droplet
output "public_ip_server_dbcluster01" {  value = digitalocean_droplet.dbcluster01.ipv4_address }
output "public_ip_server_dbcluster02" {  value = digitalocean_droplet.dbcluster02.ipv4_address }
output "public_ip_server_dbcluster03" {  value = digitalocean_droplet.dbcluster03.ipv4_address }
' > output_dbservers.tf

### apply changes to digital ocean ###
terraform apply -auto-approve

### vars databases ###
# private ips
dbcluster01_ip=`terraform output private_ip_server_dbcluster01`
dbcluster02_ip=`terraform output private_ip_server_dbcluster02`
dbcluster03_ip=`terraform output private_ip_server_dbcluster03`
# public ips
dbcluster01_ip_pub=`terraform output public_ip_server_dbcluster01`
dbcluster02_ip_pub=`terraform output public_ip_server_dbcluster02`
dbcluster03_ip_pub=`terraform output public_ip_server_dbcluster03`

# create db_ips file for proxysql deployment #
echo "dbcluster01_ip:$dbcluster01_ip" > ${OUTPUT_DIR}/db_ips.txt
echo "dbcluster02_ip:$dbcluster02_ip" >> ${OUTPUT_DIR}/db_ips.txt
echo "dbcluster03_ip:$dbcluster03_ip" >> ${OUTPUT_DIR}/db_ips.txt

# create db_hosts file for ansible database replica setup #
echo "[galeracluster]" > ${OUTPUT_DIR}/db_hosts.txt
echo "dbcluster01 ansible_ssh_host=$dbcluster01_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt
echo "dbcluster02 ansible_ssh_host=$dbcluster02_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt
echo "dbcluster03 ansible_ssh_host=$dbcluster03_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt

# wait until databases are fully deployed #
verify_python=`rpm -qa | grep python-2.7`
if [[ "${verify_python}" == "python-2.7"* ]] ; then
echo "$verify_python is installed!"
else
   sudo yum install python -y
fi

verify_git=`rpm -qa | grep git-1`
if [[ "${verify_git}" == "git"* ]] ; then
echo "$verify_git is installed!"
else
   sudo yum install git -y
fi

verify_pip=`pip -V`
if [[ "${verify_pip}" == "pip"* ]] ; then
echo "$verify_pip is installed!"
else
   curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python
fi

### install ansible #####
verify_ansible=`ansible --version`
if [[ "${verify_ansible}" == "ansible"* ]] ; then
echo "$verify_ansible is installed!"
else
  sudo pip install ansible --upgrade
  ansible --version
fi

sleep 30

# MariaDB Galera Cluster installation setup #
git clone https://github.com/emersongaudencio/ansible-percona-xtradb-cluster.git
cd ansible-percona-xtradb-cluster/ansible
priv_key="/root/repos/ansible_keys/ansible"
#### MariaDB deployment variables ####
GTID=$(($RANDOM))
echo $GTID > GTID
PXC_VERSION="80"
echo $PXC_VERSION > PXC_VERSION
CLUSTER_NAME="pxc80"
echo $CLUSTER_NAME > CLUSTER_NAME
#### MariaDB deployment ansible hosts variables ####
echo "[galeracluster]" > hosts
echo "dbcluster01 ansible_ssh_host=$dbcluster01_ip_pub" >> hosts
echo "dbcluster02 ansible_ssh_host=$dbcluster02_ip_pub" >> hosts
echo "dbcluster03 ansible_ssh_host=$dbcluster03_ip_pub" >> hosts
#### private key link ####
ln -s $priv_key ansible
#### Execution section ####
sudo sh run_xtradb_galera_install.sh dbcluster01 $PXC_VERSION $GTID "$dbcluster01_ip" "$CLUSTER_NAME" "$dbcluster01_ip,$dbcluster02_ip,$dbcluster03_ip"
sleep 30
sudo sh run_xtradb_galera_install.sh dbcluster02 $PXC_VERSION $GTID "$dbcluster01_ip" "$CLUSTER_NAME" "$dbcluster01_ip,$dbcluster02_ip,$dbcluster03_ip"
sleep 30
sudo sh run_xtradb_galera_install.sh dbcluster03 $PXC_VERSION $GTID "$dbcluster01_ip" "$CLUSTER_NAME" "$dbcluster01_ip,$dbcluster02_ip,$dbcluster03_ip"

# setup proxysql user for monitoring purpose #
ansible -i hosts -m shell -a "mysql -N -e \"CREATE USER 'proxysqlchk'@'%' IDENTIFIED BY 'Test123?dba'; GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'proxysqlchk'@'%';\"" dbcluster01 -o > setup_galeracluster_proxysql_user.txt

echo "Database deployment has been completed successfully!"
