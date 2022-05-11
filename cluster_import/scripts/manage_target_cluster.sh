#!/bin/bash
##------------------------------------------------------------------------------
## Licensed Materials - Property of IBM
## 5737-E67
## (C) Copyright IBM Corporation 2019 All Rights Reserved.
## US Government Users Restricted Rights - Use, duplication or
## disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
##------------------------------------------------------------------------------
## This script is used to manage operations pertaining to the relationship
## between a MCM hub-cluster and a target Kubernetes cluster:
##   - Import a Kubernetes cluster into the MCM hub-cluster
##   - Remove a Kubernetes cluster from the MCM hub-cluster
##
## Target Kubernetes clusters are supported within the following environments:
##   - Microsoft Azure Kubernetes Service (AKS)
##   - Amazon Elastic Kubernetes Service (EKS)
##   - Google Kubernetes Engine (GKE)
##   - IBM Cloud Kubernetes Service (IKS)
##   - IBM Cloud Private (ICP)
##   - IBM Cloud Private with Openshift (OCP)
##
## Details pertaining to the actions to be taken and target cluster to be
## managed should be provided via the following command-line parameters or <environment variable>:
## Required:
##   -ac|--action <ACTION>                          Action to be taken; Valid values include (import, remove)
##   -wd|--workdir <WORK_DIR>                       Directory where temporary work files will be created during the action
##   -hs|--hubserverurl <OCP_URL>                   OCP API URL (including port) of the OCP used by hub-cluster
##   -hu|--hubuser <OCP_USER>                       User name for connecting to the OCP used byhub-cluster
##   -hp|--hubpassword <OCP_PASSWORD>               Password used to authenticate with the OCP used by hub-cluster
##   -hc|--hubcacert <OCP_CA_CERT>                  CA cert used to authenticate with the OCP used by hub-cluster
##   -cn|--clustername <CLUSTER_NAME>               Name of the target cluster
##   -ce|--clusterendpoint <CLUSTER_ENDPOINT>       URL for accessing the target cluster
##   -cu|--clusteruser <CLUSTER_USER>               Username for accessing the target cluster
##   -ck|--clustertoken <CLUSTER_TOKEN>             Authorization token for accessing the target cluster
##   -cc|--clustercreds <CLUSTER_CREDENTIALS>       JSON-formated file containing cluster endpoint, user and token information;
##                                                  Supercedes the individual cluster endpoint, user and token inputs
##   
##------------------------------------------------------------------------------

set -e

## Perform cleanup tasks prior to exit
function exitOnError() {
    errMessage=$1
    echo "${WARN_ON}${errMessage}; Exiting...${WARN_OFF}"
    exit 1
}

## Download and install the cloudctl utility used to import/remove the managed cluster
function installCloudctlLocally() {
    if [ ! -x ${WORK_DIR}/bin/hub-cloudctl ]; then
        echo "Installing cloudctl into ${WORK_DIR}..."
        wget --quiet --no-check-certificate ${HUB_URL}/api/cli/cloudctl-linux-amd64 -P ${WORK_DIR}/bin
        mv ${WORK_DIR}/bin/cloudctl-linux-amd64 ${WORK_DIR}/bin/hub-cloudctl
        chmod +x ${WORK_DIR}/bin/hub-cloudctl
    else
        echo "cloudctl has already been installed; No action taken"
    fi
}

## Download and install the kubectl utility used to import/remove the managed cluster
function installKubectlLocally() {
    ## This script should be running with a unique HOME directory; Initialize '.kube' directory
    rm -rf   ${WORK_DIR}/bin/.kube
    mkdir -p ${WORK_DIR}/bin/.kube

    ## Install kubectl, if necessary
    if [ ! -x ${WORK_DIR}/bin/kubectl ]; then
        if [ "${KUBE_CTL_VERSION}" == "latest" ]
        then
            kversion=$(wget -qO- https://storage.googleapis.com/kubernetes-release/release/stable.txt)
        else
            kversion=${KUBE_CTL_VERSION}
        fi
        ARCH="amd64"
        CURRENTARCH=`arch`
        if [[ "$CURRENTARCH" == "ppc64le" ]]
        then
           ARCH="ppc64le"
        fi
        if [[ "$CURRENTARCH" == "s390x" ]]
        then
           ARCH="s390x"
        fi        
        echo "Installing kubectl (version ${kversion}) into ${WORK_DIR}..."
        wget --quiet https://storage.googleapis.com/kubernetes-release/release/${kversion}/bin/linux/${ARCH}/kubectl -P ${WORK_DIR}/bin
        chmod +x ${WORK_DIR}/bin/kubectl
    else
        echo "kubectl has already been installed; No action taken"
    fi
}

## Download and install the oc client 4.3
function installOCLocally() {
    if [ ! -x ${WORK_DIR}/bin/oc ]; then
        echo "Installing oc into ${WORK_DIR}..."
        wget --quiet --no-check-certificate ${OCP_CLI_ENDPOINT} -P ${WORK_DIR}/bin
        FILENAME=$(basename ${OCP_CLI_ENDPOINT})
        tar xvf ${WORK_DIR}/bin/${FILENAME} -C ${WORK_DIR}/bin
        if [ -f "${WORK_DIR}/bin/oc" ]
        then
            chmod +x ${WORK_DIR}/bin/oc
        fi
        if [ -f "${WORK_DIR}/bin/kubectl" ]
        then
            chmod +x ${WORK_DIR}/bin/kubectl
        fi        
    else
        echo "oc client has already been installed; No action taken"
    fi
}

## Verify that required details pertaining to the MCM hub-cluster have been provided
function verifyMcmHubClusterInformation() {
	ISTOKEN="false"
	ISUSER="false"
	ISPASSWORD="false"
    if [ -z "$(echo "${OCP_URL}" | tr -d '[:space:]')" ]; then
        exitOnError "OCP API URL is not available"
    fi
	if [ -z "$(echo "${OCP_TOKEN}" | tr -d '[:space:]')" ]; then
		echo "OCP token is not available"
        ISTOKEN="false"
	else
		ISTOKEN="true"
    fi    
    if [ -z "$(echo "${OCP_USER}" | tr -d '[:space:]')" ]; then
		echo "OCP user is not available"		
        ISUSER="false"
	else
		ISUSER="true"
    fi
    if [ -z "$(echo "${OCP_PASSWORD}" | tr -d '[:space:]')" ]; then
		echo "OCP password is not available"		
        ISPASSWORD="false"
	else
		ISPASSWORD="true"
    fi
    if [[ "${ISTOKEN}" == "false" && ( "${ISUSER}" == "false" || "${ISPASSWORD}" == "false") ]]; then
    	exitOnError "OCP token or user/password is not available"
	fi
	if [ -z "$(echo "${OCP_CA_CERT}" | tr -d '[:space:]')" ]; then
        echo "OCP CA Certificate is not available"
	else
		echo "${OCP_CA_CERT}" | base64 -d > ${WORK_DIR}/cert
    fi    
    installOCLocally
}

## Parse the cluster credentials from specified file
function parseTargetClusterCredentials() {
    echo "Parsing cluster credentials from ${CLUSTER_CREDENTIALS}..."
    if [ -f "${CLUSTER_CREDENTIALS}" ]; then
         ## Credentials provided via JSON file; Parse endpoint, user and token from file for later verification
         CLUSTER_ENDPOINT=$(cat ${CLUSTER_CREDENTIALS} | jq -r '.endpoint')
         CLUSTER_USER=$(cat ${CLUSTER_CREDENTIALS}     | jq -r '.user')
         CLUSTER_TOKEN=$(cat ${CLUSTER_CREDENTIALS}    | jq -r '.token')
    fi
}

## Verify the information needed to access the target cluster
function verifyTargetClusterInformation() {
    ## Verify details for accessing to the target cluster
    if [ -z "$(echo "${CLUSTER_NAME}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster name has not been specified; Exiting..."
    fi
    if [ -z "$(echo "${CLUSTER_ENDPOINT}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster server URL has not been specified; Exiting..."
    fi
    if [ -z "$(echo "${CLUSTER_USER}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster user has not been specified; Exiting..."
    fi
    if [ -z "$(echo "${CLUSTER_TOKEN}" | tr -d '[:space:]')" ]; then
        exitOnError "Authorization token has not been specified; Exiting..."
    fi

    ## Configure kubectl
    installKubectlLocally
    ${WORK_DIR}/bin/kubectl config set-cluster     ${CLUSTER_NAME} --insecure-skip-tls-verify=true --server=${CLUSTER_ENDPOINT} --kubeconfig ${WORK_DIR}/bin/.kube/config
    ${WORK_DIR}/bin/kubectl config set-credentials ${CLUSTER_USER} --token=${CLUSTER_TOKEN} --kubeconfig ${WORK_DIR}/bin/.kube/config
    ${WORK_DIR}/bin/kubectl config set-context     ${CLUSTER_NAME} --user=${CLUSTER_USER} --namespace=kube-system --cluster=${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config
    ${WORK_DIR}/bin/kubectl config use-context     ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config

    ## Generate KUBECONFIG file to be used when accessing the target cluster
    ${WORK_DIR}/bin/kubectl config view --minify=true --flatten=true --kubeconfig ${WORK_DIR}/bin/.kube/config > ${KUBECONFIG_FILE}

    verifyTargetClusterAccess
}

## Verify the target cluster can be accessed
function verifyTargetClusterAccess() {
    set +e
    echo "Verifying access to target cluster..."
    export KUBECONFIG=${KUBECONFIG_FILE}
    ${WORK_DIR}/bin/kubectl get nodes
    if [ $? -ne 0 ]; then
        exitOnError "Unable to access the target cluster; Exiting..."
    fi
    unset KUBECONFIG
    set -e
}

## Authenticate with MCM hub-cluster in order to perform import/remove operations
function ocClusterLogin() {
    echo "Logging into the hub cluster OCP ..."
    ISTOKEN="false"
	ISUSER="false"
	ISPASSWORD="false"
	OCLOGIN="--kubeconfig ${WORK_DIR}/bin/.kube/config"
	if [ -z "$(echo "${OCP_TOKEN}" | tr -d '[:space:]')" ]; then
		echo "OCP token is not available"
        ISTOKEN="false"
	else
		ISTOKEN="true"
    fi    
    if [ -z "$(echo "${OCP_USER}" | tr -d '[:space:]')" ]; then
		echo "OCP user is not available"		
        ISUSER="false"
	else
		ISUSER="true"
    fi
    if [ -z "$(echo "${OCP_PASSWORD}" | tr -d '[:space:]')" ]; then
		echo "OCP password is not available"		
        ISPASSWORD="false"
	else
		ISPASSWORD="true"
    fi
	if [ -z "$(echo "${OCP_CA_CERT}" | tr -d '[:space:]')" ]; then
        OCLOGIN="${OCLOGIN} --insecure-skip-tls-verify=true"
	else
		OCLOGIN="${OCLOGIN} --certificate-authority=${WORK_DIR}/cert"
    fi    
    if [[ "${ISTOKEN}" == "true" ]]; then
		OCLOGIN="${OCLOGIN} --token ${OCP_TOKEN}"
	elif [[ "${ISUSER}" == "true" && "${ISPASSWORD}" == "true" ]]; then
    	OCLOGIN="${OCLOGIN} --username=${OCP_USER} --password=${OCP_PASSWORD}"
	else
		exitOnError "OCP token or user/password is missing"
	fi
	
	${WORK_DIR}/bin/oc login ${OCP_URL} ${OCLOGIN}
}

## Logout from the MCM hub-cluster
function ocClusterLogout() {
	if [ -z "$(echo "${OCP_TOKEN}" | tr -d '[:space:]')" ]; then
		echo "Logging out of OC on hub cluster..."
    	${WORK_DIR}/bin/oc logout --kubeconfig ${WORK_DIR}/bin/.kube/config
	else
		echo "OCP token is used for login. Do not logout to protect token from being deleted."
    fi

}

## Prepare for the target cluster to be imported into the hub cluster:
##   - Create configuration file
##   - Create cluster resource
##   - Generate import file to be applied to target cluster
function prepareClusterImport() {
    ## Connect to hub cluster
    ocClusterLogin

    echo "Create new project ${CLUSTER_NAME} ..."
    ${WORK_DIR}/bin/oc new-project ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config
    echo "Add label to new project ${CLUSTER_NAME} ..."
    ${WORK_DIR}/bin/oc label namespace ${CLUSTER_NAME} cluster.open-cluster-management.io/managedCluster=${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config

	echo "Create managed cluster ${CLUSTER_NAME} ..."    
	${WORK_DIR}/bin/oc apply -f ${MANAGED_CLUSTER_FILE} --kubeconfig ${WORK_DIR}/bin/.kube/config
	
	echo "Create KlusterletAddonConfig for ${CLUSTER_NAME} ..."    
	${WORK_DIR}/bin/oc apply -f ${KLUSTERLET_ADD_CONFIG_FILE} --kubeconfig ${WORK_DIR}/bin/.kube/config	 
   
    IMPORT_STATUS="created"
	
	echo "Verify if secret ${CLUSTER_NAME}-import generated..."	
    iterationCount=1
    iterationInterval=10
    maxMinutes=20
    iterationMax=$((maxMinutes * 60 / iterationInterval))
    set +e
    while [ ${iterationCount} -lt ${iterationMax} ]; do
		${WORK_DIR}/bin/oc get secret ${CLUSTER_NAME}-import -n ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config
		RC=$?
		if [[ $RC -eq 0 ]]; then
        	break	
    	else
            echo "Secret ${CLUSTER_NAME}-import not created; Waiting for next check..."
            iterationCount=$((iterationCount + 1))
            sleep ${iterationInterval}	    	    		
    	fi
	done
	set -e
	echo "Generating klusterlet-crd file for target cluster ${CLUSTER_NAME}..."
	${WORK_DIR}/bin/oc get secret ${CLUSTER_NAME}-import -n ${CLUSTER_NAME} -o jsonpath={.data.crds\\.yaml} --kubeconfig ${WORK_DIR}/bin/.kube/config | base64 --decode > ${KLUSTERLET_CRD_FILE}
	echo "Klusterlet CRD file for target cluster created"
    #echo "==============================================="
    #cat ${KLUSTERLET_CRD_FILE}
    #echo "==============================================="
    	
	echo "Generating import file for target cluster ${CLUSTER_NAME}..."
	${WORK_DIR}/bin/oc get secret ${CLUSTER_NAME}-import -n ${CLUSTER_NAME} -o jsonpath={.data.import\\.yaml} --kubeconfig ${WORK_DIR}/bin/.kube/config | base64 --decode > ${IMPORT_FILE}
    echo "Import file for target cluster created"
    #echo "==============================================="
    #cat ${IMPORT_FILE}
    #echo "==============================================="
    
    IMPORT_STATUS="prepared"

    ## Disconnect from hub cluster.
    ocClusterLogout
}

## Initiate the import of the target cluster
function initiateClusterImport() {
    echo "Applying import file to target cluster ${CLUSTER_NAME}..."
    export KUBECONFIG=${KUBECONFIG_FILE}
	set +e
	
	${WORK_DIR}/bin/kubectl apply -f ${KLUSTERLET_CRD_FILE}
	RC=$?
	if [[ $RC -ne 0 ]]; then          
      	exitOnError "Unable to apply the CRD to target cluster"
	fi	
	
	${WORK_DIR}/bin/kubectl apply -f ${IMPORT_FILE}
	RC=$?	
    if [[ $RC -ne 0 ]]; then
        exitOnError "Unable to apply the import file to target cluster. Exiting ..."
    fi
    
    IMPORT_STATUS="applied"

	## Check status, waiting for success/failure status
    iterationCount=1
    iterationInterval=15
    maxMinutes=20
    iterationMax=$((maxMinutes * 60 / iterationInterval))
    while [ ${iterationCount} -lt ${iterationMax} ]; do
		echo "==============================================="
	    echo "open-cluster-management-agent pod status on managed cluster"
	    ${WORK_DIR}/bin/kubectl get pod --no-headers -n open-cluster-management-agent --ignore-not-found
	    echo "==============================================="
	    RUNNING_PODS=`${WORK_DIR}/bin/kubectl get pod --no-headers -n open-cluster-management-agent --ignore-not-found --field-selector=status.phase=Running | wc -l`   
	    if [ "${RUNNING_PODS}" -gt 0 ]; then
			echo "==============================================="
		    echo "open-cluster-management-agent pod status on managed cluster"	    	
	    	${WORK_DIR}/bin/kubectl get pod --no-headers -n open-cluster-management-agent --ignore-not-found
	    	echo "==============================================="
	    	break
		else
            echo "open-cluster-management-agent pod status is not RUNNING ; Waiting for next check..."
            iterationCount=$((iterationCount + 1))
            sleep ${iterationInterval}	    	
		fi 	
	done
    unset KUBECONFIG
    set -e
}

## Monitor the import status of the target cluster
function monitorClusterImport() {
    echo "Monitoring the import status of target cluster ${CLUSTER_NAME}..."

    ## Connect to hub cluster
    ocClusterLogin

    ## Check status, waiting for success/failure status
    iterationCount=1
    iterationInterval=15
    maxMinutes=20
    iterationMax=$((maxMinutes * 60 / iterationInterval))
    set +e
    while [ ${iterationCount} -lt ${iterationMax} ]; do
    	echo "Checking cluster join and availability status; Iteration ${iterationCount}..."
    	${WORK_DIR}/bin/kubectl get managedcluster ${CLUSTER_NAME} -n ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config
		ManagedClusterJoined=`${WORK_DIR}/bin/kubectl get managedcluster ${CLUSTER_NAME} -n ${CLUSTER_NAME} -o jsonpath={.status.conditions[?"("@.type==\"ManagedClusterJoined\"")"].status} --kubeconfig ${WORK_DIR}/bin/.kube/config`
    	ManagedClusterConditionAvailable=`${WORK_DIR}/bin/kubectl get managedcluster ${CLUSTER_NAME} -n ${CLUSTER_NAME} -o jsonpath={.status.conditions[?"("@.type==\"ManagedClusterConditionAvailable\"")"].status} --kubeconfig ${WORK_DIR}/bin/.kube/config`    	
        echo "Current cluster join status is: ${ManagedClusterJoined}"
        echo "Current cluster join status is: ${ManagedClusterConditionAvailable}"
        if [ "${ManagedClusterJoined}" == "True" -a "${ManagedClusterConditionAvailable}" == "True" ]; then
            ## Status changed; Prepare to exit loop
            break
        else
            echo "Status has not changed; Waiting for next check..."
            iterationCount=$((iterationCount + 1))
            sleep ${iterationInterval}
        fi
    done
    set -e
    if [ "${ManagedClusterJoined}" != "True" -o "${ManagedClusterConditionAvailable}" != "True" ]; then
        echo "${WARN_ON}Cluster is not ready within the allotted time; Exiting...${WARN_OFF}"
        echo "${WARN_ON}State of target cluster shown below:${WARN_OFF}"
        ${WORK_DIR}/bin/kubectl get managedcluster ${CLUSTER_NAME} -n ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config
        exit 1
    else
        echo "Import of cluster ${CLUSTER_NAME} is successful"
        IMPORT_STATUS="imported"
    fi

    ## Disconnect from hub cluster
    ocClusterLogout
}

## Remove the target cluster from the hub cluster.
function initiateClusterRemoval() {
    ## Connect to hub cluster
    ocClusterLogin

    indicatorFile=${WORK_DIR}/.cluster_deleted
    iterationCount=1
    iterationInterval=15
    maxMinutes=20
    iterationMax=$((maxMinutes * 60 / iterationInterval))
    rm -f ${indicatorFile}

    echo "Initiating removal of target cluster ${CLUSTER_NAME}..."
    (${WORK_DIR}/bin/oc delete managedcluster ${CLUSTER_NAME} --kubeconfig ${WORK_DIR}/bin/.kube/config; touch ${indicatorFile}) &
    while [ ! -f ${indicatorFile}  -a  ${iterationCount} -lt ${iterationMax} ]; do
        echo "Waiting for removal of target cluster ${CLUSTER_NAME}..."
        if [ -f ${indicatorFile} ]; then
            ## Indicator exists; Prepare to exit loop
            iterationCount=${iterationMax}
        else
            echo "Cluster delete still in progress; Waiting for next check..."
            iterationCount=$((iterationCount + 1))
            sleep ${iterationInterval}
        fi
    done
    if [ ! -f ${indicatorFile} ]; then
        exitOnError "Cluster was not deleted within the allotted time; Exiting..."
    else
        echo "Delete of cluster ${CLUSTER_NAME} was successful"
        IMPORT_STATUS="deleted"
    fi

    ## Disconnect from hub cluster
    ocClusterLogout
}

## Perform the requested cluster management operation
function performRequestedAction() {
    if [ "${ACTION}" == "import" ]; then
        prepareClusterImport
        initiateClusterImport
        monitorClusterImport
    elif [ "${ACTION}" == "remove" ]; then
        initiateClusterRemoval
    else 
        exitOnError "Unsupported management action - ${ACTION}"
    fi
}

## Perform the tasks required to complete the cluster management operation
function run() {
    ## Prepare work directory and install common utilities
    mkdir -p ${WORK_DIR}/bin
    export PATH=${WORK_DIR}/bin:${PATH}

    ## Check provided hub and target cluster information
    verifyMcmHubClusterInformation
    parseTargetClusterCredentials
    if [ "${ACTION}" == "import" ]; then
        verifyTargetClusterInformation
    elif [ "${ACTION}" == "remove" ]; then
        if [ -z "$(echo "${CLUSTER_NAME}" | tr -d '[:space:]')" ]; then
            exitOnError "Target cluster name was not provided"
        fi
    fi

    ## Perform Kubernetes service-specific tasks for the requested action
    performRequestedAction
}

##------------------------------------------------------------------------------------------------
##************************************************************************************************
##------------------------------------------------------------------------------------------------

## Gather information provided via the command line parameters
while test ${#} -gt 0; do
    [[ $1 =~ ^-ac|--action ]]           && { ACTION="${2}";                      shift 2; continue; };
    [[ $1 =~ ^-wd|--workdir ]]          && { WORK_DIR="${2}";                    shift 2; continue; };
    [[ $1 =~ ^-cn|--clustername ]]      && { CLUSTER_NAME="${2}";                shift 2; continue; };
    [[ $1 =~ ^-hs|--hubserverurl ]]     && { OCP_URL="${2}";                     shift 2; continue; };
    [[ $1 =~ ^-hu|--hubuser ]]          && { OCP_USER="${2}";                    shift 2; continue; };
    [[ $1 =~ ^-hp|--hubpassword ]]      && { OCP_PASSWORD="${2}";                shift 2; continue; };
    [[ $1 =~ ^-hc|--hubcacert ]]        && { OCP_CA_CERT="${2}";                 shift 2; continue; };    	
    [[ $1 =~ ^-ht|--hubtoken  ]]        && { OCP_TOKEN="${2}";                   shift 2; continue; };    	
    [[ $1 =~ ^-ce|--clusterendpoint ]]  && { CLUSTER_ENDPOINT="${2}";            shift 2; continue; };
    [[ $1 =~ ^-cu|--clusteruser ]]      && { CLUSTER_USER="${2}";                shift 2; continue; };
    [[ $1 =~ ^-ck|--clustertoken ]]     && { CLUSTER_TOKEN="${2}";               shift 2; continue; };
    [[ $1 =~ ^-cc|--clustercreds ]]     && { CLUSTER_CREDENTIALS="${2}";         shift 2; continue; };


    break;
done
ACTION="$(echo "${ACTION}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
if [ "${ACTION}" != "import"  -a  "${ACTION}" != "remove" ]; then
    exitOnError "Management action (e.g. import, remove) has not been specified"
fi
if [ -z "$(echo "${WORK_DIR}" | tr -d '[:space:]')" ]; then
    exitOnError "Location of the work directory has not been specified"
fi

if [ "${ACTION}" == "import" ]; then
	sed -i -e "s/@cluster_name@/${CLUSTER_NAME}/" ${WORK_DIR}/klusterletaddonconfig.yaml
	sed -i -e "s/@cluster_name@/${CLUSTER_NAME}/" ${WORK_DIR}/managedcluster.yaml
fi
		

## Prepare work directory
mkdir -p ${WORK_DIR}/bin
export PATH=${WORK_DIR}/bin:${PATH}

## Set default variable values
IMPORT_STATUS="unknown"
MANAGED_CLUSTER_FILE=${WORK_DIR}/managedcluster.yaml
KLUSTERLET_ADD_CONFIG_FILE=${WORK_DIR}/klusterletaddonconfig.yaml
KLUSTERLET_CRD_FILE=${WORK_DIR}/klusterlet-crd.yaml
IMPORT_FILE=${WORK_DIR}/import.yaml
KUBECONFIG_FILE=${WORK_DIR}/kubeconfig.yaml
WARN_ON='\033[0;31m'
WARN_OFF='\033[0m'

## Run the necessary action(s)
run
