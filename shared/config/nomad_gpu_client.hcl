# GPU-enabled Nomad client configuration
# This is a specialized client configuration for nodes with NVIDIA GPUs

data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"
datacenter = "dc1"

advertise {
  http = "IP_ADDRESS"
  rpc  = "IP_ADDRESS"
  serf = "IP_ADDRESS"
}

acl {
  enabled = true
}

client {
  enabled = true
  
  # Node class to identify GPU nodes
  node_class = "gpu"
  
  # Meta attributes for GPU nodes
  meta {
    "gpu_enabled" = "true"
    "gpu_type" = "nvidia"
  }
  
  options {
    "driver.raw_exec.enable"    = "1"
    "docker.privileged.enabled" = "true"
  }
  
  server_join {
    retry_join = ["RETRY_JOIN"]
  }
}

# NVIDIA GPU device plugin configuration
plugin "nomad-device-nvidia" {
  config {
    enabled            = true
    fingerprint_period = "1m"
    # Optionally ignore specific GPUs if needed
    # ignored_gpu_ids    = ["GPU-uuid1", "GPU-uuid2"]
  }
} 