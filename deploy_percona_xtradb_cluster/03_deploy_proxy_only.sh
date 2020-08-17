#!/bin/bash
### output directory ###
OUTPUT_DIR="output"
if [ ! -d ${OUTPUT_DIR} ]; then
    mkdir -p ${OUTPUT_DIR}
    chmod 755 ${OUTPUT_DIR}
fi
### vars databases ###
dbcluster01_ip=$(cat ${OUTPUT_DIR}/db_ips.txt | grep dbcluster01 | awk -F ":" {'print $2'})
dbcluster02_ip=$(cat ${OUTPUT_DIR}/db_ips.txt | grep dbcluster02 | awk -F ":" {'print $2'})
dbcluster03_ip=$(cat ${OUTPUT_DIR}/db_ips.txt | grep dbcluster03 | awk -F ":" {'print $2'})

### deploy proxysql ###
echo "resource \"digitalocean_droplet\" \"proxysql01\" {
    image = \"centos-7-x64\"
    name = \"proxysql01\"
    region = \"lon1\"
    size = \"s-3vcpu-1gb\"
    user_data = \"#!/bin/bash\ncurl -sS https://raw.githubusercontent.com/emersongaudencio/general-deployment-scripts/master/automation/install_ansible_proxysql2_galera.sh | sudo bash\"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}" > proxysql01.tf

echo "resource \"digitalocean_droplet\" \"proxysql02\" {
    image = \"centos-7-x64\"
    name = \"proxysql02\"
    region = \"lon1\"
    size = \"s-3vcpu-1gb\"
    user_data = \"#!/bin/bash\ncurl -sS https://raw.githubusercontent.com/emersongaudencio/general-deployment-scripts/master/automation/install_ansible_proxysql2_galera.sh | sudo bash\"
    private_networking = true
    ssh_keys = [
      var.ssh_fingerprint
]
}" > proxysql02.tf

echo '# Output the private IP address of the new droplet
output "private_ip_server_proxysql01" {  value = digitalocean_droplet.proxysql01.ipv4_address_private }
output "private_ip_server_proxysql02" {  value = digitalocean_droplet.proxysql02.ipv4_address_private }

# Output the public IP address of the new droplet
output "public_ip_server_proxysql01" {  value = digitalocean_droplet.proxysql01.ipv4_address }
output "public_ip_server_proxysql02" {  value = digitalocean_droplet.proxysql02.ipv4_address }
' > output_proxyservers.tf

### apply changes to digital ocean ###
terraform apply -auto-approve

### vars proxysql ###
# private ips
proxysql01_ip=`terraform output private_ip_server_proxysql01`
proxysql02_ip=`terraform output private_ip_server_proxysql02`
# public ips
proxysql01_ip_pub=`terraform output public_ip_server_proxysql01`
proxysql02_ip_pub=`terraform output public_ip_server_proxysql02`

# create db_ips file for proxysql deployment #
echo "proxysql01:$proxysql01_ip" > ${OUTPUT_DIR}/proxy_ips.txt
echo "proxysql02:$proxysql02_ip" >> ${OUTPUT_DIR}/proxy_ips.txt

# create db_hosts file for ansible database replica setup #
echo "[proxyservers]" > ${OUTPUT_DIR}/proxy_hosts.txt
echo "proxysql01 ansible_ssh_host=$proxysql01_ip_pub" >> ${OUTPUT_DIR}/proxy_hosts.txt
echo "proxysql02 ansible_ssh_host=$proxysql02_ip_pub" >> ${OUTPUT_DIR}/proxy_hosts.txt

# wait until databases are fully deployed #
sleep 120

# Database servers hosts setup using ansbile for automation purpose #
export ANSIBLE_HOST_KEY_CHECKING=False
priv_key="/root/repos/ansible_keys/ansible"
ansible -i ${OUTPUT_DIR}/proxy_hosts.txt -m shell -a 'echo "{{ dbcluster01_ip }} dbnode01.cluster.local" >> /etc/hosts && echo "{{ dbcluster02_ip }} dbnode02.cluster.local" >> /etc/hosts && echo "{{ dbcluster03_ip }} dbnode03.cluster.local" >> /etc/hosts; cat /etc/hosts' proxysql01 -u root --private-key=$priv_key --become -e "{dbcluster01_ip: '$dbcluster01_ip', dbcluster02_ip: '$dbcluster02_ip', dbcluster03_ip: '$dbcluster03_ip'}" -o > ${OUTPUT_DIR}/setup_proxy_dbservers_px1.txt
ansible -i ${OUTPUT_DIR}/proxy_hosts.txt -m shell -a 'echo "{{ dbcluster01_ip }} dbnode01.cluster.local" >> /etc/hosts && echo "{{ dbcluster02_ip }} dbnode02.cluster.local" >> /etc/hosts && echo "{{ dbcluster03_ip }} dbnode03.cluster.local" >> /etc/hosts; cat /etc/hosts' proxysql02 -u root --private-key=$priv_key --become -e "{dbcluster01_ip: '$dbcluster01_ip', dbcluster02_ip: '$dbcluster02_ip', dbcluster03_ip: '$dbcluster03_ip'}" -o > ${OUTPUT_DIR}/setup_proxy_dbservers_px2.txt

echo "ProxySQL deployment has been completed successfully!"
