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
  	command = "cp ${path.module}/scripts/klusterletaddonconfig.tmpl ${var.work_directory}/klusterletaddonconfig.yaml && cp ${path.module}/scripts/managedcluster.tmpl ${var.work_directory}/managedcluster.yaml"
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
      OCP_TOKEN					  = var.ocp_token

      ## Cluster details
      CLUSTER_ENDPOINT            = var.cluster_endpoint
      CLUSTER_USER                = var.cluster_user
      CLUSTER_TOKEN               = var.cluster_token
      CLUSTER_CREDENTIALS         = var.cluster_credentials

      ## Private docker registry
      IMAGE_REGISTRY              = var.image_registry
      IMAGE_SUFFIX                = var.image_suffix
      IMAGE_VERSION               = var.image_version
      DOCKER_USER                 = var.docker_user
      DOCKER_PASSWORD             = var.docker_password
    }
  }
}

resource "null_resource" "remove-cluster" {
  depends_on = [null_resource.wait-for-prerequisite]

  provisioner "local-exec" {
    when    = destroy
    command = "chmod 755 ${path.module}/scripts/manage_target_cluster.sh && ${path.module}/scripts/manage_target_cluster.sh -ac remove"
    environment = {
      ## Required
      WORK_DIR           = var.work_directory
      CLUSTER_NAME       = var.cluster_name
      OCP_URL            = var.ocp_api_endpoint
      OCP_USER           = var.ocp_user
      OCP_PASSWORD       = var.ocp_password
      OCP_CA_CERT        = var.ocp_ca_cert
      OCP_TOKEN			 = var.ocp_token      
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