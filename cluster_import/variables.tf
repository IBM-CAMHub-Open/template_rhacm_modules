variable "dependsOn" {
   description = "Variable to force dependency between modules"
   default     = "true"
}

variable "ocp_api_endpoint" {
  description = "Red Hat OCP API Endpoint URL used in oc login command. Example https://api.<>:<port>."
}

variable "ocp_token" {
  description = "Token for connecting to the Red Hat OCP using oc login command."
}

variable "ocp_user" {
  description = "Username for connecting to the Red Hat OCP using oc login command."
}

variable "ocp_password" {
  description = "Password for connecting to the Red Hat OCP using oc login command."
}

variable "ocp_ca_cert" {
  description = "OCP certificate authority certificate to be used in oc login command"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = ""
}

variable "cluster_endpoint" {
  description = "URL for the Kubernetes cluster endpoint"
  default = ""
}

variable "cluster_user" {
  description = "Username for accessing the Kubernetes cluster"
  default = ""
}

variable "cluster_token" {
  description = "Token for authenticating with the Kubernetes cluster"
  default = ""
}

variable "cluster_credentials" {
  description = "JSON-formatted file containing the cluster name, endpoint, user and token information"
  default = ""
}

variable "work_directory" {
  description = "Path of the temporary directory where work files will be generated"
  default = ""
}

variable "oc_cli_endpoint" {
  description = "URL to download OC CLI tar file"
  default = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
}

variable "kube_ctl_version" {
  description = "kubectl to use for import operations"
  default     = "latest"
}