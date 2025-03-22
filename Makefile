# Variables
PROJECT_ID ?= $(shell gcloud config get-value project)
REGION ?= us-central1
ZONE ?= us-central1-a
CLUSTER_NAME ?= logging-cluster
K8S_NAMESPACE = logging

# Terraform directories
TERRAFORM_DIR = terraform

# Terraform commands
.PHONY: tf-init
tf-init:
	@echo "Initializing Terraform..."
	cd $(TERRAFORM_DIR) && terraform init

.PHONY: tf-plan
tf-plan:
	@echo "Planning Terraform changes..."
	cd $(TERRAFORM_DIR) && terraform plan \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="cluster_name=$(CLUSTER_NAME)"

.PHONY: tf-apply
tf-apply:
	@echo "Applying Terraform changes..."
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="cluster_name=$(CLUSTER_NAME)"

.PHONY: tf-destroy
tf-destroy:
	@echo "Destroying Terraform resources..."
	cd $(TERRAFORM_DIR) && terraform destroy \
		-var="project_id=$(PROJECT_ID)" \
		-var="region=$(REGION)" \
		-var="zone=$(ZONE)" \
		-var="cluster_name=$(CLUSTER_NAME)"

# Get cluster credentials (after terraform apply)
.PHONY: get-credentials
get-credentials:
	@echo "Getting cluster credentials..."
	gcloud container clusters get-credentials $(CLUSTER_NAME) --zone=$(ZONE) --project=$(PROJECT_ID)

# Install ArgoCD
.PHONY: install-argocd
install-argocd: get-credentials
	@echo "Installing ArgoCD..."
	@bash scripts/install-argocd.sh

# Apply custom resources
.PHONY: apply-custom-resources
apply-custom-resources: get-credentials
	@echo "Applying custom resources..."
	kubectl apply -f k8s/custom-resources/namespace.yaml
	kubectl apply -f k8s/custom-resources/storage-class.yaml
	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && terraform output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < k8s/custom-resources/workload-identity.yaml | kubectl apply -f -

# Deploy root ArgoCD application (which deploys all other applications)
.PHONY: deploy-argocd-apps
deploy-argocd-apps: get-credentials
	@echo "Deploying ArgoCD applications..."
	kubectl apply -f k8s/argocd/root-application.yaml

# Process Helm values files with environment variables
.PHONY: process-helm-values
process-helm-values:
	@echo "Processing Helm values files..."
	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && terraform output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < helm-values/loki/values-dev.yaml.template > helm-values/loki/values-dev.yaml

	GCS_BUCKET_NAME=$(shell cd $(TERRAFORM_DIR) && terraform output -raw gcs_bucket_name) \
	PROJECT_ID=$(PROJECT_ID) \
	envsubst < helm-values/vector/values-dev.yaml.template > helm-values/vector/values-dev.yaml

# Deploy ingress after applications are deployed
.PHONY: deploy-ingress
deploy-ingress: get-credentials
	@echo "Deploying ingress..."
	kubectl apply -f k8s/custom-resources/ingress.yaml

# Get Grafana admin password
.PHONY: get-grafana-password
get-grafana-password: get-credentials
	@echo "Grafana admin password:"
	kubectl get secret --namespace $(K8S_NAMESPACE) grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Port forward to Grafana
.PHONY: grafana-port-forward
grafana-port-forward: get-credentials
	@echo "Port forwarding to Grafana (http://localhost:3000)..."
	kubectl port-forward --namespace $(K8S_NAMESPACE) svc/grafana 3000:80

# Port forward to ArgoCD
.PHONY: argocd-port-forward
argocd-port-forward: get-credentials
	@echo "Port forwarding to ArgoCD (https://localhost:8080)..."
	kubectl port-forward svc/argocd-server -n argocd 8080:443

# Infrastructure setup
.PHONY: setup-infra
setup-infra: tf-init tf-apply

# Full setup and deployment
.PHONY: full-deploy
full-deploy: setup-infra get-credentials install-argocd process-helm-values apply-custom-resources deploy-argocd-apps deploy-ingress
	@echo "Deployment complete. Wait for all resources to be created."
	@echo "Run 'make grafana-port-forward' to access Grafana UI."
	@echo "Run 'make argocd-port-forward' to access ArgoCD UI."

# Clean up all resources
.PHONY: clean
clean: tf-destroy
	@echo "All resources have been destroyed."
