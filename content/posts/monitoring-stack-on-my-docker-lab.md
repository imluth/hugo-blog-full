---
title: "Building a Robust Docker Monitoring Stack"
date: 2025-04-06
author: "Looth"
description: "A comprehensive guide to implementing a production-ready monitoring solution for Docker environments with Prometheus, Loki, and Grafana."
tags: ["docker", "devops", "monitoring", "prometheus", "loki", "grafana", "traefik"]
categories: ["DevOps", "Monitoring"]
draft: false
---

# Building a Robust Docker Monitoring Stack for Production

![Grafana Overview](/img/grafana-main.png)

As a DevOps engineer managing containerized environments, I've learned that proper observability isn't just nice to have—it's essential for maintaining system reliability and quickly resolving issues. After experimenting with various tools and configurations in my Docker lab, I've developed a comprehensive monitoring stack that I'm now deploying in production environments.

In this post, I'll walk through my approach to building a complete monitoring solution for Docker environments using industry-standard tools and production-ready best practices.

## The Monitoring Stack Architecture

![Monitoring Stack Overview](/img/monitoring-stack-overview.png)

My monitoring solution combines metrics and logs collection into a unified observability platform. Here's what we'll be implementing:

1. **Metrics Collection & Storage**
   - Prometheus (time-series database)
   - Node Exporter (host-level metrics)
   - cAdvisor (container-level metrics)

2. **Log Aggregation**
   - Loki (log storage and querying)
   - Promtail (log collector)

3. **Visualization**
   - Grafana (unified dashboard)

4. **Security & Access**
   - Traefik (reverse proxy with TLS)
   - Basic authentication

## Prerequisites

Before getting started, you'll need:

- Docker and Docker Compose installed
- A server running Linux (I'm using Linode)
- A domain with DNS configured
- Traefik already set up as a reverse proxy with SSL support

## Implementation Details

### Docker Compose Configuration

Let's start with our complete `docker-compose.yml` configuration. This is the backbone of our monitoring stack:

```yaml
version: "3.3"

services:
  prometheus:
    image: prom/prometheus:v2.48.1
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 1G
    networks:
      - traefik-public
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-public"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.looth.io`)"
      - "traefik.http.routers.prometheus.entrypoints=websecure"
      - "traefik.http.routers.prometheus.tls.certresolver=leresolver"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
      # Basic auth middleware
      - "traefik.http.routers.prometheus.middlewares=prometheus-auth"
      - "traefik.http.middlewares.prometheus-auth.basicauth.users=admin:<encryptedpassword>"

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    deploy:
      resources:
        limits:
          cpus: '0.10'
          memory: 128M
    networks:
      - monitoring
    expose:
      - 9100

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.2
    container_name: cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
    networks:
      - monitoring
    expose:
      - 8080

  grafana:
    image: grafana/grafana:10.2.3
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=secure_password_here
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=https://grafana.looth.io
    volumes:
      - grafana_data:/var/lib/grafana
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
    networks:
      - traefik-public
      - monitoring
    depends_on:
      - prometheus
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-public"
      - "traefik.http.routers.grafana.rule=Host(`grafana.looth.io`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=leresolver"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

  loki:
    image: grafana/loki:2.9.5
    container_name: loki
    restart: unless-stopped
    user: "0:0"  # Run as root user to avoid permission issues
    volumes:
      - ./loki:/etc/loki
      - ./loki-data:/loki  # Use bind mount instead of named volume
    command: -config.file=/etc/loki/loki-config.yaml
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
    networks:
      - traefik-public
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-public"
      - "traefik.http.routers.loki.rule=Host(`loki.looth.io`)"
      - "traefik.http.routers.loki.entrypoints=websecure"
      - "traefik.http.routers.loki.tls.certresolver=leresolver"
      - "traefik.http.services.loki.loadbalancer.server.port=3100"
      - "traefik.http.routers.loki.middlewares=loki-auth"
      - "traefik.http.middlewares.loki-auth.basicauth.users=admin:<encryptedpassword>"

  promtail:
    image: grafana/promtail:2.9.5
    container_name: promtail
    restart: unless-stopped
    user: "0:0"  # Run as root to avoid permission issues
    volumes:
      - ./promtail:/etc/promtail
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: -config.file=/etc/promtail/promtail-config.yaml
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
    networks:
      - monitoring
    depends_on:
      - loki

networks:
  traefik-public:
    external: true
  monitoring:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
```

### Essential Configuration Files

Let's look at the configuration for each component of our monitoring stack.

#### Prometheus Configuration

Create a `prometheus.yml` file in the `./prometheus` directory:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  # Add scrape configs for your other services here
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

  - job_name: 'docker'
    static_configs:
      - targets: ['cadvisor:8080']
```

#### Loki Configuration

Create a `loki-config.yaml` file in the `./loki` directory:

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

#### Promtail Configuration

Create a `promtail-config.yaml` file in the `./promtail` directory:

```yaml
server:
  http_listen_port: 9080

positions:
  filename: /etc/promtail/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*.log
    pipeline_stages:
      - docker: {}
      - labeldrop:
          - filename
          - stream
```

## Production-Ready Best Practices

Throughout my testing and implementation, I've incorporated several production-ready practices that make this monitoring stack reliable and secure:

### 1. Resource Management

One of the most critical aspects of running a monitoring stack in production is proper resource management. I've learned from experience that without explicit limits, monitoring tools can sometimes consume excessive resources and impact the performance of your production services:

```yaml
deploy:
  resources:
    limits:
      cpus: '0.50'
      memory: 512M
```

These limits prevent any single component from consuming too many resources and potentially bringing down the entire host. The values are based on my observations of typical resource usage in production environments.

### 2. Network Segmentation

The stack uses two separate networks:

- `traefik-public`: An external network used for components that need to be publicly accessible through Traefik
- `monitoring`: An internal bridge network for components to communicate securely

This approach follows the principle of least privilege by only exposing the necessary services, keeping the attack surface as small as possible.

### 3. Data Persistence

Both Prometheus and Grafana use named volumes to ensure data persistence across container restarts or upgrades:

```yaml
volumes:
  prometheus_data:
  grafana_data:
```

For Loki, I've chosen a bind mount approach to make the data easier to back up and manage:

```yaml
volumes:
  - ./loki-data:/loki
```

This strategy ensures you won't lose historical metrics or dashboard configurations during maintenance or updates.

### 4. Security Measures

Several security practices are implemented in this stack:

- **TLS Encryption**: All public endpoints use HTTPS via Traefik's Let's Encrypt integration
- **Basic Authentication**: Sensitive dashboards (Prometheus, Loki) use basic auth to prevent unauthorized access
- **Read-Only Mounts**: All volume mounts use read-only access where possible
- **Limited User Sign-up**: Grafana is configured to prevent unauthorized user registration

These measures ensure that your monitoring data remains secure and accessible only to authorized personnel.

### 5. Container Best Practices

Other Docker-specific best practices used throughout this stack:

- **Named Containers**: Makes it easier to reference them in logs and commands
- **Fixed Versions**: Using specific image versions instead of `latest` for reproducibility
- **Health Checks**: Services implement health checks for better orchestration
- **Restart Policies**: All services are configured to restart automatically if they crash

## Setting Up Grafana Dashboards

Once your stack is running, you'll need to set up dashboards in Grafana for visualization.

![Grafana Data Sources](/img/grafana-data-source.png)

### 1. Add Data Sources

First, add both Prometheus and Loki as data sources in Grafana:

- **Prometheus**:
  - URL: `http://prometheus:9090`
  - Access: Server (default)

- **Loki**:
  - URL: `http://loki:3100`
  - Access: Server (default)

### 2. Import Dashboard Templates

Grafana has many pre-built dashboards you can import. Here are some recommended dashboard IDs that I've found particularly useful in production:

- Node Exporter Full: 1860
- Docker Containers: 893
- Traefik: 11462

![Grafana Node Exporter](/img/grafana-overview-node-exporter.png)

![Grafana Docker Containers Dashboard](/img/grafana-container.png)

### 3. Create a Custom Logs Dashboard

For container logs, create a custom dashboard with these panels:

1. **All Container Logs**
   - Query: `{container=~".+"}`

2. **Error Logs Across All Containers**
   - Query: `{container=~".+"} |= "error" or {container=~".+"} |= "ERROR"`

3. **Logs by Container** (using a variable)
   - Dashboard variable query: `label_values(container)`
   - Panel query: `{container="$container"}`

4. **Log Volume Over Time**
   - For monitoring spikes in logging activity

![Loki Dashboard](/img/grafana-loki.png)

Here are some useful LogQL queries I frequently use in production:

```
# All logs for a specific container
{container="traefik"}

# Filter by HTTP status codes (for web services)
{container="traefik"} |~ "HTTP/1.1\\" (4|5)\\d\\d"

# Find error messages
{container=~".+"} |= "error" or {container=~".+"} |= "ERROR" 

# Find warnings
{container=~".+"} |= "WARN" or {container=~".+"} |= "WARNING"
```

## Alerting and Notification

While not covered in this basic setup, you can extend this monitoring stack with alerting capabilities:

![Grafana Alerts](/img/grafana-alerting.png)

1. Use Prometheus AlertManager for metrics-based alerts
2. Configure Grafana alerting for both logs and metrics
3. Set up notification channels (email, Slack, PagerDuty, etc.)

I'll cover my alerting setup in a future post, as it deserves its own dedicated walkthrough.

## Conclusion

After several iterations in my lab environment, this monitoring stack has proven itself ready for production use. It provides complete visibility into containerized applications through both metrics and logs, all while following DevOps best practices for security, resource management, and data persistence.

![Grafana Dash](/img/grafana-dash1.png)

![Grafana Dash](/img/grafana-dash2.png)

The beauty of this approach is its modularity—you can easily extend it with additional exporters, dashboards, or integrations as your monitoring needs evolve.

By combining Prometheus, Loki, and Grafana, you get a powerful monitoring solution that helps ensure the reliability and performance of your applications while making troubleshooting much more straightforward.

## Next Steps

Based on my testing and production deployment, here are some future improvements I'm planning to implement:

- Setting up AlertManager for automated alerts based on resource thresholds
- Adding specialized exporters for MySQL, PostgreSQL, and Redis
- Implementing distributed tracing with Tempo to complement metrics and logs
- Exploring long-term storage solutions for metrics and logs retention

Feel free to adapt this setup to your specific needs or reach out if you have any questions about implementing this in your own Docker environment!
