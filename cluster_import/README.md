# Modules to import kubernetes cluster into Red Hat Advanced Cluster Management. 
Copyright IBM Corp. 2020, 2020
This code is released under the Apache 2.0 License.

## Overview
This terraform template imports an existing Kubernetes cluster into Red Hat Advanced Cluster Management (RHACM) 2.0.0.
Supported Kubernetes cluster environments include:
* IBM Cloud Private with Openshift (OCP) 4.2
* IBM Cloud Kubernetes Service (IKS)
* Microsoft Azure Kubernetes Service (AKS)
* Google Cloud Kubernetes Engine (GKE)
* Amazon EC2 Kubernetes Service (EKS)

## Prerequisites
* Tiller should not be installed within the Kubernetes cluster

## Automation summary
The terraform template performs the following activities to import the specified Kubernetes cluster into the RHACM:
* Authenticates with the OCP server hosting the RHACM enabled CP4MCM
* Uses the given Kubernetes cluster details to configure the import process

## Template input parameters

| Parameter Name                  | Parameter Description | Required |
| :---                            | :--- | :--- |
| ocp_api_endpoint                | Red Hat OCP API Endpoint URL used in oc login command. Example https://api.<>:<port>. | true |
| ocp_user                		  | Username for connecting to the Red Hat OCP using oc login command. | true |
| ocp_password                    | Password for connecting to the Red Hat OCP using oc login command. | true |
| ocp_ca_cert                     | OCP certificate authority certificate to be used in oc login command. | false |
| cluster_name                    | Name of the target cluster to be imported into the MCM hub cluster. Cluster name can have lower case alphabets, numbers and dash. Must start with lower case alphabet and end with alpha-numeric character. Maximum length is 63 characters. Defaults to input kubeconfig data object cluster name. | true |
| cluster_endpoint                | URL for the target Kubernetes cluster endpoint. | true |
| cluster_user                    | Username for accessing the target Kubernetes cluster. | true |
| cluster_token                   | Token for authenticating with the target Kubernetes cluster. | true |
| cluster_credentials             | JSON-formatted file containing the cluster name, endpoint, user and token information.| | 
| work_directory				  | Path of the temporary directory where work files will be generated. | | 
| kube_ctl_version                | kubectl client version to connect to server | | 