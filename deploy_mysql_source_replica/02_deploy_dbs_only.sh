#!/bin/bash
### output directory ###
OUTPUT_DIR="output"
if [ ! -d ${OUTPUT_DIR} ]; then
    mkdir -p ${OUTPUT_DIR}
    chmod 755 ${OUTPUT_DIR}
fi
### deploy databases ###
echo 'resource "digitalocean_droplet" "dbprimary01" {
    image = "centos-7-x64"
    name = "dbprimary01"
    region = "lon1"
    size = "s-4vcpu-8gb"
    user_data = "#!/bin/bash\ncurl -sS https://raw.githubusercontent.com/emersongaudencio/general-deployment-scripts/master/automation/install_ansible_mysql_80.sh | sudo bash"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbprimary01.tf

echo 'resource "digitalocean_droplet" "dbreplica01" {
    image = "centos-7-x64"
    name = "dbreplica01"
    region = "lon1"
    size = "s-4vcpu-8gb"
    user_data = "#!/bin/bash\ncurl -sS https://raw.githubusercontent.com/emersongaudencio/general-deployment-scripts/master/automation/install_ansible_mysql_80.sh | sudo bash"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbreplica01.tf

echo 'resource "digitalocean_droplet" "dbreplica02" {
    image = "centos-7-x64"
    name = "dbreplica02"
    region = "lon1"
    size = "s-4vcpu-8gb"
    user_data = "#!/bin/bash\ncurl -sS https://raw.githubusercontent.com/emersongaudencio/general-deployment-scripts/master/automation/install_ansible_mysql_80.sh | sudo bash"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}' > dbreplica02.tf

echo '# Output the private IP address of the new droplet
output "private_ip_server_dbprimary01" {  value = digitalocean_droplet.dbprimary01.ipv4_address_private }
output "private_ip_server_dbreplica01" {  value = digitalocean_droplet.dbreplica01.ipv4_address_private }
output "private_ip_server_dbreplica02" {  value = digitalocean_droplet.dbreplica02.ipv4_address_private }

# Output the public IP address of the new droplet
output "public_ip_server_dbprimary01" {  value = digitalocean_droplet.dbprimary01.ipv4_address }
output "public_ip_server_dbreplica01" {  value = digitalocean_droplet.dbreplica01.ipv4_address }
output "public_ip_server_dbreplica02" {  value = digitalocean_droplet.dbreplica02.ipv4_address }
' > output_dbservers.tf

### apply changes to digital ocean ###
terraform apply -auto-approve

### vars databases ###
# private ips
dbprimary01_ip=`terraform output private_ip_server_dbprimary01`
dbreplica01_ip=`terraform output private_ip_server_dbreplica01`
dbreplica02_ip=`terraform output private_ip_server_dbreplica02`
# public ips
dbprimary01_ip_pub=`terraform output public_ip_server_dbprimary01`
dbreplica01_ip_pub=`terraform output public_ip_server_dbreplica01`
dbreplica02_ip_pub=`terraform output public_ip_server_dbreplica02`

# create db_ips file for proxysql deployment #
echo "dbprimary01:$dbprimary01_ip" > ${OUTPUT_DIR}/db_ips.txt
echo "dbreplica01:$dbreplica01_ip" >> ${OUTPUT_DIR}/db_ips.txt
echo "dbreplica02:$dbreplica02_ip" >> ${OUTPUT_DIR}/db_ips.txt

# create db_hosts file for ansible database replica setup #
echo "[dbservers]" > ${OUTPUT_DIR}/db_hosts.txt
echo "dbprimary01 ansible_ssh_host=$dbprimary01_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt
echo "dbreplica01 ansible_ssh_host=$dbreplica01_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt
echo "dbreplica02 ansible_ssh_host=$dbreplica02_ip_pub" >> ${OUTPUT_DIR}/db_hosts.txt

# wait until databases are fully deployed #
sleep 600

# replication setup using ansbile for automation purpose #
export ANSIBLE_HOST_KEY_CHECKING=False
priv_key="/root/repos/ansible_keys/ansible"
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "mysql -N -e 'show master status'" dbprimary01 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_master_position.txt
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "cat /root/.my.cnf | grep replication_user" dbprimary01 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_user_master.txt
# get replication_credentials info
rep_user=$(cat ${OUTPUT_DIR}/setup_replication_user_master.txt | awk -F "|" {'print $4'} | awk {'print $3'})
rep_pwd=$(cat ${OUTPUT_DIR}/setup_replication_user_master.txt | awk -F "|" {'print $4'} | awk {'print $6'})
# get replication file info #
log_file=$(cat ${OUTPUT_DIR}/setup_replication_master_position.txt | awk -F "|" {'print $4'} | awk {'print $2'})
log_position=$(cat ${OUTPUT_DIR}/setup_replication_master_position.txt | awk -F "|" {'print $4'} | awk {'print $3'})
gtid_position=$(cat ${OUTPUT_DIR}/setup_replication_master_position.txt | awk -F "|" {'print $4'} | awk {'print $4'})
# setup replica read_only = ON #
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "mysql -N -e 'set global read_only = 1; select @@read_only;'; echo '# readonly-mode' >> /etc/my.cnf && echo 'read_only = 1' >> /etc/my.cnf && echo 'innodb_flush_log_at_trx_commit = 2' >> /etc/my.cnf && echo 'log_slave_updates = 0' >> /etc/my.cnf ;" dbreplica01 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_dbreplica01_read_only.txt
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "mysql -N -e 'set global read_only = 1; select @@read_only;'; echo '# readonly-mode' >> /etc/my.cnf && echo 'read_only = 1' >> /etc/my.cnf && echo 'innodb_flush_log_at_trx_commit = 2' >> /etc/my.cnf && echo 'log_slave_updates = 0' >> /etc/my.cnf ;" dbreplica02 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_dbreplica02_read_only.txt
# setup replication on replica servers #
master_host=$(cat ${OUTPUT_DIR}/db_ips.txt | grep dbprimary01 | awk -F ":" {'print $2'})
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a 'mysql -N -e "CHANGE MASTER TO master_host=\"{{ master_host }}\", master_port=3306, master_user=\"{{ master_user }}\", master_password = \"{{ master_password }}\", MASTER_AUTO_POSITION=0; CHANGE MASTER TO MASTER_LOG_FILE=\"{{ master_log_file }}\", MASTER_LOG_POS={{ master_log_pos }}; START SLAVE; SHOW SLAVE STATUS\G"' dbreplica01 -u root --private-key=/root/repos/ansible_keys/ansible --become -e "{master_host: '$master_host', master_user: '$rep_user' , master_password: '$rep_pwd', master_log_file: '$log_file' , master_log_pos: '$log_position' }" -o > ${OUTPUT_DIR}/setup_replication_dbreplica01_activation.txt
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a 'mysql -N -e "CHANGE MASTER TO master_host=\"{{ master_host }}\", master_port=3306, master_user=\"{{ master_user }}\", master_password = \"{{ master_password }}\", MASTER_AUTO_POSITION=0; CHANGE MASTER TO MASTER_LOG_FILE=\"{{ master_log_file }}\", MASTER_LOG_POS={{ master_log_pos }}; START SLAVE; SHOW SLAVE STATUS\G"' dbreplica02 -u root --private-key=/root/repos/ansible_keys/ansible --become -e "{master_host: '$master_host', master_user: '$rep_user' , master_password: '$rep_pwd', master_log_file: '$log_file' , master_log_pos: '$log_position' }" -o > ${OUTPUT_DIR}/setup_replication_dbreplica02_activation.txt

ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a 'mysql -N -e "STOP SLAVE; SET GLOBAL gtid_purged=\"{{ gtid }}\"; CHANGE MASTER TO MASTER_AUTO_POSITION=1; START SLAVE; SHOW SLAVE STATUS;"' dbreplica01 -u root --private-key=/root/repos/ansible_keys/ansible --become -e "{ gtid: '$gtid_position'}" -o > ${OUTPUT_DIR}/setup_replication_dbreplica01_activation_phase2.txt
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a 'mysql -N -e "STOP SLAVE; SET GLOBAL gtid_purged=\"{{ gtid }}\"; CHANGE MASTER TO MASTER_AUTO_POSITION=1; START SLAVE; SHOW SLAVE STATUS;"' dbreplica02 -u root --private-key=/root/repos/ansible_keys/ansible --become -e "{ gtid: '$gtid_position'}" -o > ${OUTPUT_DIR}/setup_replication_dbreplica02_activation_phase2.txt
# setup proxysql user for monitoring purpose #
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "mysql -N -e \"CREATE USER 'proxysqlchk'@'%' IDENTIFIED BY 'Test123?dba'; GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'proxysqlchk'@'%';\"" dbprimary01 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_proxysql_user.txt
# restart replicas #
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "sudo service mysqld restart" dbreplica01 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_dbreplica01_restart.txt
ansible -i ${OUTPUT_DIR}/db_hosts.txt -m shell -a "sudo service mysqld restart" dbreplica02 -u root --private-key=$priv_key --become -o > ${OUTPUT_DIR}/setup_replication_dbreplica02_restart.txt

echo "Database deployment has been completed successfully!"
