#!/bin/bash
# Skrypt do budowania i wypychania obrazu Docker na stacji zewnętrznej
# Wymaga: Docker Desktop, Azure CLI, dostęp do internetu

set -e  # Przerwij przy błędzie

# ============================================================================
# KONFIGURACJA - ZMIEŃ TE WARTOŚCI
# ============================================================================

# Nazwa ACR i wersja obrazu
ACR_NAME="acrgithubrunersprod"
IMAGE_NAME="actions-runner-custom"
IMAGE_VERSION="1.0.11"  # <-- ZWIĘKSZ WERSJĘ przy każdym buildzie!

# Pełna nazwa obrazu
FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_VERSION}"

# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================

print_step() {
    echo ""
    echo "======================================================================"
    echo "⚙️  $1"
    echo "======================================================================"
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ BŁĄD: $1"
    exit 1
}

# ============================================================================
# WALIDACJA ŚRODOWISKA
# ============================================================================

print_step "Walidacja środowiska"

# Sprawdź czy jesteśmy w odpowiednim katalogu
if [ ! -f "Dockerfile" ]; then
    print_error "Nie znaleziono Dockerfile. Uruchom skrypt z katalogu docker/runner-image/"
fi

# Sprawdź czy katalog certificates istnieje
if [ ! -d "../../certificates" ]; then
    print_error "Katalog certificates/ nie istnieje"
fi

# Sprawdź czy wszystkie wymagane certyfikaty istnieją
REQUIRED_CERTS=(
    "../../certificates/pekao-root-ca.crt"
    "../../certificates/pekao-level2.crt"
    "../../certificates/github-server.crt"
    "../../certificates/proxy-intermediate-ca.crt"
)

for cert in "${REQUIRED_CERTS[@]}"; do
    if [ ! -f "$cert" ]; then
        print_error "Brak wymaganego certyfikatu: $cert"
    fi
done

print_success "Wszystkie wymagane certyfikaty znalezione"

# Sprawdź czy Docker działa
if ! docker info > /dev/null 2>&1; then
    print_error "Docker nie jest uruchomiony. Włącz Docker Desktop."
fi

print_success "Docker jest uruchomiony"

# Sprawdź czy Azure CLI jest zainstalowane
if ! command -v az &> /dev/null; then
    print_error "Azure CLI nie jest zainstalowane. Zainstaluj z: https://aka.ms/InstallAzureCLIDeb"
fi

print_success "Azure CLI jest zainstalowane"

# ============================================================================
# BUDOWANIE OBRAZU
# ============================================================================

print_step "Budowanie obrazu Docker"

echo "Obraz: ${FULL_IMAGE_NAME}"
echo "Kontekst budowania: $(pwd)"
echo ""

# Buduj obraz - używamy kontekstu z głównego katalogu repo aby mieć dostęp do certificates/
docker build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --tag "${FULL_IMAGE_NAME}" \
    --tag "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest" \
    --file Dockerfile \
    .

print_success "Obraz zbudowany pomyślnie"

# Pokaż rozmiar obrazu
echo ""
docker images "${ACR_NAME}.azurecr.io/${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ============================================================================
# LOGOWANIE DO ACR
# ============================================================================

print_step "Logowanie do Azure Container Registry"

echo "ACR: ${ACR_NAME}.azurecr.io"
echo ""
echo "UWAGA: Musisz mieć dostęp do tego ACR."
echo "Jeśli nie masz bezpośredniego dostępu, poproś administratora o utworzenie tokena."
echo ""

# Opcja 1: Logowanie przez Azure CLI (wymaga VPN/dostępu do sieci Azure)
read -p "Czy masz bezpośredni dostęp do ACR przez VPN? (t/n): " has_vpn

if [[ "$has_vpn" == "t" || "$has_vpn" == "T" ]]; then
    echo "Logowanie przez Azure CLI..."
    az acr login --name "${ACR_NAME}"
    print_success "Zalogowano przez Azure CLI"
else
    # Opcja 2: Logowanie przez token
    echo ""
    echo "Musisz użyć tokena dostępu. Poproś administratora o uruchomienie:"
    echo ""
    echo "  az acr token create --name external-build-token \\"
    echo "    --registry ${ACR_NAME} \\"
    echo "    --scope-map _repositories_admin \\"
    echo "    --expiration-in-days 1"
    echo ""
    echo "A następnie wygenerowanie hasła:"
    echo ""
    echo "  az acr token credential generate --name external-build-token \\"
    echo "    --registry ${ACR_NAME} \\"
    echo "    --password1"
    echo ""

    read -p "Podaj nazwę tokena (domyślnie: external-build-token): " token_name
    token_name=${token_name:-external-build-token}

    read -sp "Podaj hasło tokena: " token_password
    echo ""

    echo "$token_password" | docker login "${ACR_NAME}.azurecr.io" --username "$token_name" --password-stdin
    print_success "Zalogowano przez token"
fi

# ============================================================================
# WYPYCHANIE OBRAZU
# ============================================================================

print_step "Wypychanie obrazu do ACR"

# Wypchaj wersjonowany tag
docker push "${FULL_IMAGE_NAME}"
print_success "Wypchano: ${FULL_IMAGE_NAME}"

# Wypchaj tag 'latest'
docker push "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest"
print_success "Wypchano: ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest"

# ============================================================================
# WERYFIKACJA
# ============================================================================

print_step "Weryfikacja obrazu w ACR"

# Sprawdź czy obraz jest w ACR (tylko jeśli mamy dostęp przez Azure CLI)
if [[ "$has_vpn" == "t" || "$has_vpn" == "T" ]]; then
    echo "Dostępne tagi w ACR:"
    az acr repository show-tags --name "${ACR_NAME}" --repository "${IMAGE_NAME}" --output table
fi

# ============================================================================
# PODSUMOWANIE
# ============================================================================

print_step "GOTOWE! 🎉"

echo ""
echo "Obraz został zbudowany i wypchnięty pomyślnie:"
echo "  📦 Obraz: ${FULL_IMAGE_NAME}"
echo ""
echo "NASTĘPNE KROKI:"
echo ""
echo "1. Zaktualizuj wersję obrazu w Terraform:"
echo "   Edytuj: terraform/prod/devops_arc_runner.tf"
echo "   Zmień linię ~682:"
echo ""
echo "   runner_image = \"${FULL_IMAGE_NAME}\""
echo ""
echo "2. Zrób commit i push do repo:"
echo "   git add ."
echo "   git commit -m \"Update runner image to ${IMAGE_VERSION} with complete CA bundle\""
echo "   git push"
echo ""
echo "3. To uruchomi GitHub Action który zaktualizuje środowisko"
echo ""
echo "4. Po wdrożeniu, zweryfikuj certyfikaty na runnerze:"
echo "   kubectl exec -it <pod-name> -n actions-runner-system -- bash"
echo "   env | grep CERT"
echo "   curl -v https://registry.terraform.io/.well-known/terraform.json"
echo ""
