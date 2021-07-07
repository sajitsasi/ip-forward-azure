# Securely connect to an External Endpoint from Azure

## Introduction
This is a simple solution that uses an Azure Standard Load Balancer and 2 VMs to forward packets to a destination endpoint.

## Configuration
1. Standard Load Balancer is used.
2. Connectivity is from on-premises OR another VNET that is directly peered to the VNET in which the Load Balancer resides.  This example assumes connectivity from on-premises
3. Only 2 VMs are created in different Availability Zones for redundancy
4. On-premises DNS is configured to resolve the external endpoint FQDN to the frontend IP address of the Load Balancer
