FROM ghcr.io/actions/actions-runner:latest

# Switch to root for installations
USER root

# Update package list and install required tools
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    python3 \
    python3-pip \
    unzip \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform 1.9.8
RUN wget -O terraform.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && chmod +x /usr/local/bin/terraform \
    && rm terraform.zip

# Create terraform plugin cache directory
RUN mkdir -p /home/runner/.terraform.d/plugin-cache \
    && chown -R runner:runner /home/runner/.terraform.d

# Note: Corporate certificates will be loaded dynamically from ConfigMap via initContainer

# Set environment variables for .NET Core SSL handling
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Switch back to runner user
USER runner

# Set terraform plugin cache directory
ENV TF_PLUGIN_CACHE_DIR=/home/runner/.terraform.d/plugin-cache