# Loki-based Log Aggregation System on GKE

This repository contains a Terraform and Kubernetes implementation of a centralized logging solution using Grafana Loki for a startup environment running on Google Kubernetes Engine (GKE). The solution aggregates logs from multiple sources including a Next.js application on Vercel, GCP resources, managed PostgreSQL, and Databricks workloads.

## Architecture

The system architecture consists of several components that collect, process, store, and visualize log data:

- **GKE Cluster**: Hosting the core logging infrastructure
- **Vector**: Log collector and processor
- **Loki**: Log storage and indexing service
- **Grafana**: Visualization dashboard
- **Redis**: Index storage for Loki
- **Cloud Storage**: Long-term log storage
- **Pub/Sub**: Collecting logs from GCP services
- **ArgoCD**: GitOps continuous delivery

## Key Features

- **Centralized Logging**: All logs from various sources available in one place
- **Structured Logging**: Consistent log format for better querying
- **Log Retention Policies**: Configurable retention periods for different log types
- **Custom Dashboards**: Pre-configured Grafana dashboards for log analysis
- **GitOps Deployment**: Infrastructure as code with version control
- **GCP-Native Integration**: Uses GCP services for better reliability and reduced operational overhead

## Prerequisites

- Google Cloud SDK (gcloud)
- Terraform 1.0+
- kubectl
- envsubst (for environment variable substitution)
- Git

## Getting Started

1. **Clone this repository**:

   ```bash
   git clone https://github.com/your-org/loki-log-aggregation.git
   cd loki-log-aggregation
   ```

2. **Initialize and authenticate with Google Cloud**:

   ```bash
   gcloud init
   gcloud auth application-default login
   ```

3. **Set up your GCP project**:

   ```bash
   export PROJECT_ID=your-project-id
   gcloud config set project $PROJECT_ID
   ```

4. **Deploy the infrastructure**:

   ```bash
   make setup-infra
   ```

5. **Deploy the logging system**:

   ```bash
   make full-deploy
   ```

## Directory Structure

```bash
.
├── Makefile                       # Main Makefile for setup and deployment
├── README.md                      # Project documentation
├── scripts/
│   └── install-argocd.sh          # Script to install ArgoCD
├── helm-values/
│   ├── loki/
│   │   ├── values-dev.yaml        # Custom values for Loki
│   │   └── values-dev.yaml.template # Template for Loki values
│   ├── grafana/
│   │   └── values-dev.yaml        # Custom values for Grafana
│   ├── vector/
│   │   ├── values-dev.yaml        # Custom values for Vector
│   │   └── values-dev.yaml.template # Template for Vector values
│   └── redis/
│       └── values-dev.yaml        # Custom values for Redis
├── terraform/                     # Terraform infrastructure as code
│   ├── main.tf                    # Main Terraform configuration
│   ├── outputs.tf                 # Output definitions
│   ├── provider.tf                # Provider configuration
│   ├── variables.tf               # Variable definitions
│   └── versions.tf                # Terraform version constraints
└── k8s/
    ├── custom-resources/
    │   ├── namespace.yaml         # Namespace definition
    │   ├── storage-class.yaml     # GCP storage class
    │   ├── workload-identity.yaml # Workload identity bindings
    │   └── ingress.yaml           # GCP-specific ingress
    └── argocd/
        ├── root-application.yaml  # Root ArgoCD application
        ├── loki-application.yaml  # Loki ArgoCD application
        ├── grafana-application.yaml # Grafana ArgoCD application
        ├── vector-application.yaml # Vector ArgoCD application
        └── redis-application.yaml # Redis ArgoCD application
```

## Usage

### Accessing Dashboards

1. **Grafana**:
   ```
   make grafana-port-forward
   ```
   Then access: http://localhost:3000 (admin/admin)

2. **ArgoCD**:
   ```
   make argocd-port-forward
   ```
   Then access: https://localhost:8080
   
   Get the admin password:
   ```
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

### Sending Logs to the System

#### From Next.js on Vercel

Add a custom logger to your Next.js application that sends logs to the Vector HTTP endpoint:

```javascript
// logger.js
const sendLog = async (logData) => {
  try {
    await fetch('https://vector.example.com/api/logs', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        app_name: 'nextjs',
        environment: process.env.NODE_ENV,
        timestamp: new Date().toISOString(),
        level: logData.level,
        message: logData.message,
        ...logData.metadata
      }),
    });
  } catch (error) {
    console.error('Failed to send log:', error);
  }
};

export const logger = {
  info: (message, metadata = {}) => {
    sendLog({ level: 'info', message, metadata });
  },
  warn: (message, metadata = {}) => {
    sendLog({ level: 'warn', message, metadata });
  },
  error: (message, metadata = {}) => {
    sendLog({ level: 'error', message, metadata });
  }
};
```

#### From Databricks

Set up a webhook in your Databricks workspace that forwards logs to Vector's HTTP endpoint:

```python
# Example Databricks log forwarding
import requests
import json

def send_log_to_vector(log_message, log_level="INFO", metadata=None):
    if metadata is None:
        metadata = {}
    
    log_data = {
        "source": "databricks",
        "environment": "production",
        "level": log_level,
        "message": log_message,
        "timestamp": datetime.now().isoformat(),
        **metadata
    }
    
    try:
        response = requests.post(
            "https://vector.example.com/api/logs",
            headers={"Content-Type": "application/json"},
            data=json.dumps(log_data)
        )
        return response.status_code == 200
    except Exception as e:
        print(f"Failed to send log: {e}")
        return False
```

#### From GCP Resources

GCP logs are automatically collected via Pub/Sub subscription. Set up a log sink in GCP:

```
gcloud logging sinks create gcp-logging-sink pubsub.googleapis.com/projects/[PROJECT_ID]/topics/gcp-logs \
  --log-filter='resource.type="gce_instance" OR resource.type="cloudsql_database"'
```

## Configuration

### Changing Retention Policies

Edit the `helm-values/loki/values-dev.yaml` file and update the `limits_config.retention_period` value.

### Adding New Log Sources

1. Update the Vector configuration in `helm-values/vector/values-dev.yaml` to add new sources, transforms, and sinks.
2. Apply the changes using ArgoCD or kubectl.

## Monitoring the System

Access Grafana and use the pre-configured dashboards:
- "Loki Logs" dashboard for viewing logs
- "Vector Metrics" dashboard for monitoring the log pipeline

## Common Tasks

Use the Makefile for common tasks:

```bash
# Check the system status
make status

# Get Grafana admin password
make get-grafana-password

# Test the logging system
make test-logging

# Access Loki directly
make loki-port-forward

# Access Vector API
make vector-port-forward
```

## Querying Logs in Grafana

Loki uses LogQL for querying logs. Here are some examples:

```bash
# View all logs from Next.js application
{source="nextjs"}

# Filter logs by level
{source="nextjs", level="error"}

# Search for specific text
{source="nextjs"} |= "api request"

# View logs in a specific time range
{source="gcp", resource_type="cloudsql_database"} | time > unix_timestamp("2023-03-15T00:00:00Z")
```

## Troubleshooting

### Checking Component Status

```bash
# Check if all pods are running
kubectl get pods -n logging

# Check ArgoCD application status
kubectl get applications -n argocd

# View logs from a specific component
kubectl logs -n logging deployment/vector
kubectl logs -n logging statefulset/loki-0
kubectl logs -n logging deployment/grafana
```

### Common Issues

1. **Workload Identity Issues**: 
   - Check if service accounts are properly configured
   - Verify IAM bindings are correct

2. **Loki Storage Issues**:
   - Check if GCS bucket is accessible
   - Verify Loki pod has proper permissions

3. **Vector Log Collection Issues**:
   - Check Vector configuration for errors
   - Verify network connectivity to log sources

## Cleanup

To remove all resources:

```bash
make clean
```

## Security Considerations

This implementation includes:

- Workload Identity for secure GCP service access
- Network policies to restrict pod-to-pod communication
- TLS for external access
- Least privilege IAM permissions

## Contributing

Contributions are welcome! Please create a pull request with your changes.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
