# Skrypt do budowania i wypychania obrazu Docker na stacji zewnętrznej (Windows)
# Wymaga: Docker Desktop, Azure CLI, dostęp do internetu

# ============================================================================
# KONFIGURACJA - ZMIEŃ TE WARTOŚCI
# ============================================================================

$ACR_NAME = "acrgithubrunersprod"
$IMAGE_NAME = "actions-runner-custom"
$IMAGE_VERSION = "1.0.11"  # <-- ZWIĘKSZ WERSJĘ przy każdym buildzie!

$FULL_IMAGE_NAME = "$ACR_NAME.azurecr.io/$IMAGE_NAME`:$IMAGE_VERSION"

# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================

function Print-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "⚙️  $Message" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "❌ BŁĄD: $Message" -ForegroundColor Red
    exit 1
}

# ============================================================================
# WALIDACJA ŚRODOWISKA
# ============================================================================

Print-Step "Walidacja środowiska"

# Sprawdź czy jesteśmy w odpowiednim katalogu
if (-not (Test-Path "Dockerfile")) {
    Print-Error "Nie znaleziono Dockerfile. Uruchom skrypt z katalogu docker/runner-image/"
}

# Sprawdź czy katalog certificates istnieje
if (-not (Test-Path "..\..\certificates")) {
    Print-Error "Katalog certificates/ nie istnieje"
}

# Sprawdź czy wszystkie wymagane certyfikaty istnieją
$REQUIRED_CERTS = @(
    "..\..\certificates\pekao-root-ca.crt",
    "..\..\certificates\pekao-level2.crt",
    "..\..\certificates\github-server.crt",
    "..\..\certificates\proxy-intermediate-ca.crt"
)

foreach ($cert in $REQUIRED_CERTS) {
    if (-not (Test-Path $cert)) {
        Print-Error "Brak wymaganego certyfikatu: $cert"
    }
}

Print-Success "Wszystkie wymagane certyfikaty znalezione"

# Sprawdź czy Docker działa
try {
    docker info | Out-Null
    Print-Success "Docker jest uruchomiony"
} catch {
    Print-Error "Docker nie jest uruchomiony. Włącz Docker Desktop."
}

# Sprawdź czy Azure CLI jest zainstalowane
try {
    az --version | Out-Null
    Print-Success "Azure CLI jest zainstalowane"
} catch {
    Print-Error "Azure CLI nie jest zainstalowane. Zainstaluj z: https://aka.ms/InstallAzureCLIDeb"
}

# ============================================================================
# BUDOWANIE OBRAZU
# ============================================================================

Print-Step "Budowanie obrazu Docker"

Write-Host "Obraz: $FULL_IMAGE_NAME"
Write-Host "Kontekst budowania: $PWD"
Write-Host ""

# Buduj obraz
docker build `
    --build-arg BUILDKIT_INLINE_CACHE=1 `
    --tag "$FULL_IMAGE_NAME" `
    --tag "$ACR_NAME.azurecr.io/$IMAGE_NAME`:latest" `
    --file Dockerfile `
    .

if ($LASTEXITCODE -ne 0) {
    Print-Error "Budowanie obrazu nie powiodło się"
}

Print-Success "Obraz zbudowany pomyślnie"

# Pokaż rozmiar obrazu
Write-Host ""
docker images "$ACR_NAME.azurecr.io/$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ============================================================================
# LOGOWANIE DO ACR
# ============================================================================

Print-Step "Logowanie do Azure Container Registry"

Write-Host "ACR: $ACR_NAME.azurecr.io"
Write-Host ""
Write-Host "UWAGA: Musisz mieć dostęp do tego ACR."
Write-Host "Jeśli nie masz bezpośredniego dostępu, poproś administratora o utworzenie tokena."
Write-Host ""

# Pytaj użytkownika o metodę logowania
$has_vpn = Read-Host "Czy masz bezpośredni dostęp do ACR przez VPN? (t/n)"

if ($has_vpn -eq "t" -or $has_vpn -eq "T") {
    Write-Host "Logowanie przez Azure CLI..."
    az acr login --name $ACR_NAME

    if ($LASTEXITCODE -ne 0) {
        Print-Error "Logowanie przez Azure CLI nie powiodło się"
    }

    Print-Success "Zalogowano przez Azure CLI"
} else {
    # Opcja 2: Logowanie przez token
    Write-Host ""
    Write-Host "Musisz użyć tokena dostępu. Poproś administratora o uruchomienie:"
    Write-Host ""
    Write-Host "  az acr token create --name external-build-token \"
    Write-Host "    --registry $ACR_NAME \"
    Write-Host "    --scope-map _repositories_admin \"
    Write-Host "    --expiration-in-days 1"
    Write-Host ""
    Write-Host "A następnie wygenerowanie hasła:"
    Write-Host ""
    Write-Host "  az acr token credential generate --name external-build-token \"
    Write-Host "    --registry $ACR_NAME \"
    Write-Host "    --password1"
    Write-Host ""

    $token_name = Read-Host "Podaj nazwę tokena (domyślnie: external-build-token)"
    if ([string]::IsNullOrWhiteSpace($token_name)) {
        $token_name = "external-build-token"
    }

    $token_password = Read-Host "Podaj hasło tokena" -AsSecureString
    $token_password_plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token_password)
    )

    $token_password_plain | docker login "$ACR_NAME.azurecr.io" --username $token_name --password-stdin

    if ($LASTEXITCODE -ne 0) {
        Print-Error "Logowanie przez token nie powiodło się"
    }

    Print-Success "Zalogowano przez token"
}

# ============================================================================
# WYPYCHANIE OBRAZU
# ============================================================================

Print-Step "Wypychanie obrazu do ACR"

# Wypchaj wersjonowany tag
docker push "$FULL_IMAGE_NAME"
if ($LASTEXITCODE -ne 0) {
    Print-Error "Wypychanie obrazu nie powiodło się"
}
Print-Success "Wypchano: $FULL_IMAGE_NAME"

# Wypchaj tag 'latest'
docker push "$ACR_NAME.azurecr.io/$IMAGE_NAME`:latest"
if ($LASTEXITCODE -ne 0) {
    Print-Error "Wypychanie obrazu 'latest' nie powiodło się"
}
Print-Success "Wypchano: $ACR_NAME.azurecr.io/$IMAGE_NAME`:latest"

# ============================================================================
# WERYFIKACJA
# ============================================================================

Print-Step "Weryfikacja obrazu w ACR"

# Sprawdź czy obraz jest w ACR (tylko jeśli mamy dostęp przez Azure CLI)
if ($has_vpn -eq "t" -or $has_vpn -eq "T") {
    Write-Host "Dostępne tagi w ACR:"
    az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME --output table
}

# ============================================================================
# PODSUMOWANIE
# ============================================================================

Print-Step "GOTOWE! 🎉"

Write-Host ""
Write-Host "Obraz został zbudowany i wypchnięty pomyślnie:"
Write-Host "  📦 Obraz: $FULL_IMAGE_NAME"
Write-Host ""
Write-Host "NASTĘPNE KROKI:"
Write-Host ""
Write-Host "1. Zaktualizuj wersję obrazu w Terraform:"
Write-Host "   Edytuj: terraform/prod/devops_arc_runner.tf"
Write-Host "   Zmień linię ~682:"
Write-Host ""
Write-Host "   runner_image = `"$FULL_IMAGE_NAME`""
Write-Host ""
Write-Host "2. Zrób commit i push do repo:"
Write-Host "   git add ."
Write-Host "   git commit -m `"Update runner image to $IMAGE_VERSION with complete CA bundle`""
Write-Host "   git push"
Write-Host ""
Write-Host "3. To uruchomi GitHub Action który zaktualizuje środowisko"
Write-Host ""
Write-Host "4. Po wdrożeniu, zweryfikuj certyfikaty na runnerze:"
Write-Host "   kubectl exec -it <pod-name> -n actions-runner-system -- bash"
Write-Host "   env | grep CERT"
Write-Host "   curl -v https://registry.terraform.io/.well-known/terraform.json"
Write-Host ""
