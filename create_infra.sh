#!/bin/bash

PREFIX="az-cubic-test"
AZ_RG="${PREFIX}-rg"
AZ_LOCATION="eastus2"
AZ_VNET="${PREFIX}-vnet"
AZ_VNET_CIDR="10.128.0.0/22"
AZ_VNET_VM_SUBNET="vm-subnet"
AZ_VNET_VM_SUBNET_CIDR="10.128.0.0/24"
AZ_VNET_FE_SUBNET="fe-subnet"
AZ_VNET_FE_SUBNET_CIDR="10.128.1.0/24"
AZ_VNET_PLS_SUBNET="pls-subnet"
AZ_VNET_PLS_SUBNET_CIDR="10.128.2.0/24"
AZ_VNET_BASTION_SUBNET="bastion-subnet"
AZ_VNET_BASTION_SUBNET_CIDR="10.128.3.0/24"
AZ_NSG="external-nsg"
AZ_LB="${PREFIX}-lb"
AZ_LB_FE_NAME="lbFrontend"
AZ_LB_HEALTH_PROBE="SSHHealthProbe"
AZ_LB_HTTP_RULE="HTTPRule"
AZ_LB_HTTPS_RULE="HTTPSRule"
AZ_LB_BEPOOL="bepool"
AZ_NAT_GW="FWDNATGateway"
AZ_NAT_PUBLIC_IP="NATPublicIP"

GREEN="\e[01;32m"
BLUE="\e[01;36m"
RED="\e[01;31m"
NOCOL="\e[0m"
function runcmd() {
  echo -en "${BLUE}+ $@${NOCOL}">&2
  out=$($@ 2>&1)
  if [ $? -eq 0 ]; then
    echo -e "${GREEN} -- success! ${NOCOL}"
  else
    echo -e "\n${RED}${out}${NOCOL}"
    echo "exiting"
    exit -1
  fi
}

# 1. Create Azure Resource Group
runcmd "az group create --name ${AZ_RG} --location ${AZ_LOCATION}"

# 2. Create Public IP and NAT Gateway for outbound VM connectivity 
runcmd "az network public-ip create \
-g ${AZ_RG} \
--name ${AZ_NAT_PUBLIC_IP} \
--sku standard \
--allocation static"

runcmd "az network nat gateway create \
-g ${AZ_RG} \
--name ${AZ_NAT_GW} \
--public-ip-addresses ${AZ_NAT_PUBLIC_IP} \
--idle-timeout 10"

# 3. Create VNET
runcmd "az network vnet create \
  -g ${AZ_RG} \
  -n ${AZ_VNET} \
  --address-prefixes ${AZ_VNET_CIDR} \
  --subnet-name ${AZ_VNET_VM_SUBNET} \
  --subnet-prefixes ${AZ_VNET_VM_SUBNET_CIDR} \
  --location ${AZ_LOCATION}"

runcmd "az network vnet subnet update \
-g ${AZ_RG} \
--vnet-name ${AZ_VNET} \
--name ${AZ_VNET_VM_SUBNET} \
--nat-gateway ${AZ_NAT_GW}"

# 4. Create frontend subnet
runcmd "az network vnet subnet create \
  -g ${AZ_RG} \
  --vnet-name ${AZ_VNET} \
  -n ${AZ_VNET_FE_SUBNET} \
  --address-prefix ${AZ_VNET_FE_SUBNET_CIDR}"

# 5. Create PLS subnet and update PLS policies
runcmd "az network vnet subnet create \
  -g ${AZ_RG} \
  --vnet-name ${AZ_VNET} \
  -n ${AZ_VNET_PLS_SUBNET} \
  --address-prefix ${AZ_VNET_PLS_SUBNET_CIDR}"

runcmd "az network vnet subnet update \
  -g ${AZ_RG} \
  --vnet-name ${AZ_VNET} \
  -n ${AZ_VNET_PLS_SUBNET} \
  --disable-private-link-service-network-policies true"

# 6. Create Bastion subnet (Optional only if you need external connectivity)
runcmd "az network vnet subnet create \
  -g ${AZ_RG} \
  --vnet-name ${AZ_VNET} \
  -n ${AZ_VNET_BASTION_SUBNET} \
  --address-prefix ${AZ_VNET_BASTION_SUBNET_CIDR}"

# 7. Create NSG and allow SSH access from HOME_IP (Optional only if you need external connectivity)
runcmd "az network nsg create -g ${AZ_RG} --name ${AZ_NSG}"

HOME_IP="$(curl ifconfig.me)/32"
runcmd "az network nsg rule create \
  -g ${AZ_RG} \
  --nsg-name ${AZ_NSG} \
  --name "AllowSSH" \
  --direction inbound \
  --source-address-prefix ${HOME_IP} \
  --destination-port-range 22 \
  --access allow \
  --priority 500 \
  --protocol Tcp"

runcmd "az network vnet subnet update \
  -g ${AZ_RG} \
  -n ${AZ_VNET_BASTION_SUBNET} \
  --vnet-name ${AZ_VNET} \
  --network-security-group ${AZ_NSG}"

# 8. Create Bastion VM (Optional VM only needed if you need external connectivity)
runcmd "az vm create \
  -g ${AZ_RG} \
  --name bastionvm \
  --image UbuntuLTS \
  --admin-user azureuser \
  --generate-ssh-keys \
  --vnet-name ${AZ_VNET} \
  --subnet ${AZ_VNET_BASTION_SUBNET} \
  --no-wait"

# 9. Create Standard Internal Load Balancer, probe, and rules
runcmd "az network lb create \
  -g ${AZ_RG} \
  --name ${AZ_LB} \
  --sku standard \
  --vnet-name ${AZ_VNET} \
  --subnet ${AZ_VNET_FE_SUBNET} \
  --frontend-ip-name ${AZ_LB_FE_NAME} \
  --backend-pool-name ${AZ_LB_BEPOOL}"

runcmd "az network lb probe create \
  -g ${AZ_RG} \
  --lb-name ${AZ_LB} \
  --name ${AZ_LB_HEALTH_PROBE} \
  --protocol Tcp \
  --port 22"

runcmd "az network lb rule create \
  -g ${AZ_RG} \
  --lb-name ${AZ_LB} \
  --name ${AZ_LB_HTTP_RULE} \
  --protocol tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name ${AZ_LB_FE_NAME} \
  --backend-pool-name ${AZ_LB_BEPOOL} \
  --probe-name ${AZ_LB_HEALTH_PROBE}"

runcmd "az network lb rule create \
  -g ${AZ_RG} \
  --lb-name ${AZ_LB} \
  --name ${AZ_LB_HTTPS_RULE} \
  --protocol tcp \
  --frontend-port 443 \
  --backend-port 443 \
  --frontend-ip-name ${AZ_LB_FE_NAME} \
  --backend-pool-name ${AZ_LB_BEPOOL} \
  --probe-name ${AZ_LB_HEALTH_PROBE}"

# 10. Create NICs and VMs
AZ_VM_NIC="FwdVMNIC${RANDOM}"
AZ_VM_NAME="fwdvm"
AZ_LB_PRIVATE_IP=$(az network lb frontend-ip show -g ${AZ_RG} --lb-name ${AZ_LB} -n ${AZ_LB_FE_NAME} --query privateIpAddress -o tsv)
for i in `seq 1 2`; do
  NIC="${AZ_VM_NIC}${i}"
  VM="${AZ_VM_NAME}${i}"
  runcmd "az network nic create \
    -g ${AZ_RG} \
    -n ${NIC} \
    --vnet-name ${AZ_VNET} \
    --subnet ${AZ_VNET_VM_SUBNET}"

  runcmd "az vm create \
    -g ${AZ_RG} \
    -n ${VM} \
    --image UbuntuLTS \
    --admin-user azureuser \
    --generate-ssh-keys \
    --nics ${NIC} \
    --custom-data ./cloud_init.yaml"

  runcmd "az network nic ip-config address-pool add \
    -g ${AZ_RG} \
    --lb-name ${AZ_LB} \
    --address-pool ${AZ_LB_BEPOOL} \
    --ip-config-name ipconfig1 \
    --nic-name ${NIC}"

#  runcmd "az vm run-command invoke \
#    -g ${AZ_RG} \
#    --command-id RunShellScript \
#    -n ${VM} \
#    --scripts \"/usr/local/bin/ip_fwd.sh -i eth0 -f 80 -a ${AZ_LB_PRIVATE_IP} -b 80\""

#  runcmd "az vm run-command invoke \
#    -g ${AZ_RG} \
#    --command-id RunShellScript \
#    -n ${VM} \
#    --scripts \"/usr/local/bin/ip_fwd.sh -i eth0 -f 443 -a ${AZ_LB_PRIVATE_IP} -b 443\""

done

# 11. Create forwarding rules in the VMs
