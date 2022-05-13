resource "null_resource" "wait-for-prerequisite" {
  ## Trigger renewal of resource to allow for changes in prerequisite module
  triggers = {
    trigger_time = timestamp()
  }
  provisioner "local-exec" {
    ## Use the 'dependsOn var, set within prerequisite module, to force dependency to work.
    command = "echo Completed prerequisite ${var.dependsOn}"
  }
}

resource "null_resource" "import-cluster" {
  depends_on = [null_resource.wait-for-prerequisite]
  
  provisioner "local-exec" {
  	command = "mkdir -p ${var.work_directory} && cp ${path.module}/scripts/klusterletaddonconfig.tmpl ${var.work_directory}/klusterletaddonconfig.yaml && cp ${path.module}/scripts/managedcluster.tmpl ${var.work_directory}/managedcluster.yaml"
  }
  
  provisioner "local-exec" {
    command = "chmod 755 ${path.module}/scripts/manage_target_cluster.sh && ${path.module}/scripts/manage_target_cluster.sh -ac import -wd ${var.work_directory}"
    environment = {
      ## Required
      CLUSTER_NAME                = var.cluster_name
      OCP_URL                     = var.ocp_api_endpoint
      OCP_USER                    = var.ocp_user
      OCP_PASSWORD                = var.ocp_password
      OCP_CA_CERT                 = var.ocp_ca_cert
      OCP_TOKEN					          = var.ocp_token
      OCP_CLI_ENDPOINT            = var.oc_cli_endpoint
      KUBE_CTL_VERSION            = var.kube_ctl_version      

      ## Cluster details
      CLUSTER_ENDPOINT            = var.cluster_endpoint
      CLUSTER_USER                = var.cluster_user
      CLUSTER_TOKEN               = var.cluster_token
      CLUSTER_CREDENTIALS         = var.cluster_credentials
    }
  }
}

resource "null_resource" "remove-cluster" {
  depends_on = [null_resource.wait-for-prerequisite]

  triggers = {
    work_directory = var.work_directory
    cluster_name = var.cluster_name
    ocp_api_endpoint = var.ocp_api_endpoint
    ocp_user = var.ocp_user
    ocp_password = var.ocp_password
    ocp_ca_cert = var.ocp_ca_cert
    ocp_token = var.ocp_token
    oc_cli_endpoint = var.oc_cli_endpoint
    kube_ctl_version  = var.kube_ctl_version  
  }  
  provisioner "local-exec" {
    when    = destroy
    command = "chmod 755 ${path.module}/scripts/manage_target_cluster.sh && ${path.module}/scripts/manage_target_cluster.sh -ac remove"
    environment = {
      ## Required
      WORK_DIR           = self.triggers.work_directory
      CLUSTER_NAME       = self.triggers.cluster_name
      OCP_URL            = self.triggers.ocp_api_endpoint
      OCP_USER           = self.triggers.ocp_user
      OCP_PASSWORD       = self.triggers.ocp_password
      OCP_CA_CERT        = self.triggers.ocp_ca_cert
      OCP_TOKEN			     = self.triggers.ocp_token      
      OCP_CLI_ENDPOINT   = self.triggers.oc_cli_endpoint
      KUBE_CTL_VERSION   = self.triggers.kube_ctl_version      
    }
  }
}


## Log generated credentials
resource "null_resource" "credentials-generated" {
  depends_on = [null_resource.import-cluster]
  triggers = {
    trigger_time = timestamp()
  }
  provisioner "local-exec" {
    command = "echo Cluster imported: ${null_resource.import-cluster.id}"
  }
}