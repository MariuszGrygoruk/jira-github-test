FROM pakiety.dev.pekao.com.pl/artifactory/ghcr/actions/actions-runner:latest

USER root

# Instalacja Terraform i narzędzi
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    git \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Skopiuj wszystkie certyfikaty z katalogu certificates/ do obrazu
COPY ../../certificates/*.crt /tmp/certs/

# Zbuduj kompletny bundle CA
# Łączymy: Mozilla CA (146 certyfikatów) + GitHub Enterprise CA (3 certy) + Proxy CA (1 cert)
RUN cat /etc/ssl/certs/ca-certificates.crt \
        /tmp/certs/pekao-root-ca.crt \
        /tmp/certs/pekao-level2.crt \
        /tmp/certs/github-server.crt \
        /tmp/certs/proxy-intermediate-ca.crt \
        > /etc/ssl/certs/complete-ca-bundle.crt && \
    rm -rf /tmp/certs

# Ustaw zmienne środowiskowe wskazujące na kompletny bundle
ENV SSL_CERT_FILE=/etc/ssl/certs/complete-ca-bundle.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/complete-ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/complete-ca-bundle.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/complete-ca-bundle.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/complete-ca-bundle.crt

# Instalacja Terraform
ENV TERRAFORM_VERSION=1.9.8
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    && terraform version

# Instalacja Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Tworzenie katalogu cache dla Terraform
RUN mkdir -p /home/runner/.terraform.d/plugin-cache \
    && chown -R runner:runner /home/runner/.terraform.d

# Pre-cache popularnych providerów Terraform
COPY setup-terraform.sh /tmp/
RUN chmod +x /tmp/setup-terraform.sh && /tmp/setup-terraform.sh

USER runner

# Ustawienie zmiennych środowiskowych
ENV TF_PLUGIN_CACHE_DIR=/home/runner/.terraform.d/plugin-cache
ENV TERRAFORM_CLI_PATH=/usr/local/bin/terraform

# Proxy configuration - exclude Terraform registry and Azure endpoints
ENV NO_PROXY="localhost,127.0.0.1,.cluster.local,.azurecr.io,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.cn.in.pekao.com.pl,github.cn.in.pekao.com.pl,registry.terraform.io,releases.hashicorp.com,checkpoint-api.hashicorp.com,login.microsoftonline.com,management.azure.com,.azure.com,.microsoft.com,.hashicorp.com"

# Terraform SSL and proxy bypass configuration
ENV TF_TLS_SKIP_VERIFY=1
ENV CHECKPOINT_DISABLE=1
ENV GOPROXY=direct
ENV GOSUMDB=off
ENV TERRAFORM_SKIP_VERIFY=1