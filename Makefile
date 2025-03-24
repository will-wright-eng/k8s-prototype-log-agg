# Variables
PROJECT_ID ?= $(shell gcloud config get-value project)
REGION ?= us-central1
ZONE ?= us-central1-a
CLUSTER_NAME ?= logging-cluster
K8S_NAMESPACE = logging

# tofu directories
TERRAFORM_DIR = tofu

.DEFAULT_GOAL := help ##* Setup

help: ## Display this help screen
	@echo "Usage: make [command]"
	@echo ""
	@echo "Commands:"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[$$()% a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

#* tofu commands
init: ## [tf] Initialize Terraform
	@echo "Initializing Terraform..."
	cd $(TERRAFORM_DIR) && tofu init

plan: ## [tf] Plan tofu changes
	@echo "Planning tofu changes..."
	cd $(TERRAFORM_DIR) && tofu plan

apply: ## [tf] Apply tofu changes
	@echo "Applying tofu changes..."
	cd $(TERRAFORM_DIR) && tofu apply -auto-approve

destroy: ## [tf] Destroy tofu resources
	@echo "Destroying tofu resources..."
	cd $(TERRAFORM_DIR) && tofu destroy

get-credentials: ## [gcloud] Get cluster credentials (after tofu apply)
	@echo "Getting cluster credentials..."
	gcloud container clusters get-credentials $(CLUSTER_NAME) --zone=$(ZONE) --project=$(PROJECT_ID)

install-argocd: get-credentials ## [k8s] Install ArgoCD
	@echo "Installing ArgoCD..."
	@bash scripts/install-argocd.sh

apply-custom-resources: get-credentials ## [k8s] Apply custom resources
	@echo "Applying custom resources..."
	kubectl apply -f k8s/custom-resources/namespace.yaml
	kubectl apply -f k8s/custom-resources/storage-class.yaml
	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && tofu output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < k8s/custom-resources/workload-identity.yaml | kubectl apply -f -

deploy-argocd-apps: get-credentials ## [k8s] Deploy root ArgoCD application (which deploys all other applications)
	@echo "Deploying ArgoCD applications..."
	kubectl apply -f k8s/argocd/root-application.yaml

process-helm-values: ## [k8s] Process Helm values files with environment variables
	@echo "Processing Helm values files..."
	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && tofu output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < helm-values/loki/values-dev.yaml.template > helm-values/loki/values-dev.yaml

	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && tofu output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < helm-values/vector/values-dev.yaml.template > helm-values/vector/values-dev.yaml

deploy-ingress: get-credentials ## [k8s] Deploy ingress after applications are deployed
	@echo "Deploying ingress..."
	kubectl apply -f k8s/custom-resources/ingress.yaml

get-grafana-password: get-credentials ## [k8s] Get Grafana admin password
	@echo "Grafana admin password:"
	kubectl get secret --namespace $(K8S_NAMESPACE) grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

grafana-port-forward: get-credentials ## [k8s] Port forward to Grafana
	@echo "Port forwarding to Grafana (http://localhost:3000)..."
	kubectl port-forward --namespace $(K8S_NAMESPACE) svc/grafana 3000:80

argocd-port-forward: get-credentials ## [k8s] Port forward to ArgoCD
	@echo "Port forwarding to ArgoCD (https://localhost:8080)..."
	kubectl port-forward svc/argocd-server -n argocd 8080:443

setup-infra: init apply ## [tf] Infrastructure setup

full-deploy: setup-infra get-credentials install-argocd process-helm-values apply-custom-resources deploy-argocd-apps deploy-ingress ## [k8s] Full setup and deployment
	@echo "Deployment complete. Wait for all resources to be created."
	@echo "Run 'make grafana-port-forward' to access Grafana UI."
	@echo "Run 'make argocd-port-forward' to access ArgoCD UI."

clean: destroy ## [tf] Clean up all resources
	@echo "All resources have been destroyed."
