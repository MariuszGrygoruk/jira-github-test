#!/bin/bash
set -e

# Pre-cache providerów Terraform
mkdir -p /tmp/tf-init
cd /tmp/tf-init

# Tworzenie pliku konfiguracyjnego dla cache'owania providerów
cat > main.tf << EOF
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"  
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.18"
    }
  }
}
EOF

# Inicjalizacja i cache'owanie providerów
export TF_PLUGIN_CACHE_DIR=/home/runner/.terraform.d/plugin-cache
terraform init

# Czyszczenie
cd /
rm -rf /tmp/tf-init