# Budowanie obrazu Docker na stacji zewnętrznej

Ten dokument opisuje jak zbudować i wypchnąć obraz Docker runnera na stacji zewnętrznej (poza siecią korporacyjną).

## Wymagania

- **Docker Desktop** - zainstalowany i uruchomiony
- **Azure CLI** - zainstalowane ([instrukcja](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))
- **Git** - do sklonowania repozytorium
- **Dostęp do internetu** - do pobrania obrazów bazowych

## Przygotowanie

### 1. Sklonuj repozytorium

```bash
git clone <url-repozytorium>
cd azure-github-runners-infrastructure
```

### 2. Przejdź do katalogu z Dockerfile

```bash
cd docker/runner-image
```

### 3. Sprawdź certyfikaty

Upewnij się że katalog `certificates/` zawiera wszystkie wymagane certyfikaty:

```bash
ls ../../certificates/
```

Powinny być:
- `pekao-root-ca.crt` ✅
- `pekao-level2.crt` ✅
- `github-server.crt` ✅
- `proxy-intermediate-ca.crt` ✅

## Opcja A: Budowanie przez skrypt (zalecane)

### Windows (PowerShell)

```powershell
# Otwórz PowerShell jako Administrator
cd docker\runner-image

# Wykonaj skrypt
.\build-and-push.ps1
```

### Linux/Mac (Bash)

```bash
cd docker/runner-image

# Nadaj uprawnienia
chmod +x build-and-push.sh

# Wykonaj skrypt
./build-and-push.sh
```

Skrypt przeprowadzi Cię przez cały proces:
1. Walidację środowiska i certyfikatów
2. Budowanie obrazu Docker
3. Logowanie do ACR (przez VPN lub token)
4. Wypychanie obrazu do ACR
5. Weryfikację

## Opcja B: Budowanie ręczne

Jeśli wolisz kontrolować każdy krok:

### 1. Zbuduj obraz

```bash
# WAŻNE: Zwiększ wersję przy każdym buildzie!
export IMAGE_VERSION="1.0.11"

docker build \
  --tag acrgithubrunersprod.azurecr.io/actions-runner-custom:$IMAGE_VERSION \
  --tag acrgithubrunersprod.azurecr.io/actions-runner-custom:latest \
  --file Dockerfile \
  .
```

### 2. Zaloguj się do ACR

**Opcja A: Przez VPN (wymaga dostępu do sieci Azure)**

```bash
az acr login --name acrgithubrunersprod
```

**Opcja B: Przez token (bez VPN)**

Poproś administratora o utworzenie tokena:

```bash
# Administrator wykonuje w sieci korporacyjnej:
az acr token create \
  --name external-build-token \
  --registry acrgithubrunersprod \
  --scope-map _repositories_admin \
  --expiration-in-days 1

# Generuje hasło:
az acr token credential generate \
  --name external-build-token \
  --registry acrgithubrunersprod \
  --password1
```

Następnie zaloguj się używając tokena:

```bash
# Podaj nazwę tokena jako username i wygenerowane hasło
docker login acrgithubrunersprod.azurecr.io
```

### 3. Wypchnij obraz

```bash
# Wersjonowany tag
docker push acrgithubrunersprod.azurecr.io/actions-runner-custom:$IMAGE_VERSION

# Tag latest
docker push acrgithubrunersprod.azurecr.io/actions-runner-custom:latest
```

## Aktualizacja wersji w Terraform

Po zbudowaniu i wypchnięciu obrazu, zaktualizuj wersję w konfiguracji Terraform:

### 1. Edytuj plik

Otwórz `terraform/prod/devops_arc_runner.tf` i znajdź linię ~682:

```hcl
runner_image = "acrgithubrunersprod.azurecr.io/actions-runner-custom:1.0.11"
```

Zmień wersję na nową (np. `1.0.11` → `1.0.12`).

### 2. Zrób commit i push

```bash
git add .
git commit -m "Update runner image to 1.0.12 with complete CA bundle"
git push
```

To uruchomi GitHub Action, który automatycznie zaktualizuje środowisko.

## Weryfikacja po wdrożeniu

Sprawdź czy certyfikaty działają na nowym runnerze:

```bash
# Połącz się z podem runnera
kubectl exec -it <pod-name> -n actions-runner-system -- bash

# Sprawdź zmienne środowiskowe
env | grep CERT

# Powinny być ustawione:
# SSL_CERT_FILE=/etc/ssl/certs/complete-ca-bundle.crt
# CURL_CA_BUNDLE=/etc/ssl/certs/complete-ca-bundle.crt
# REQUESTS_CA_BUNDLE=/etc/ssl/certs/complete-ca-bundle.crt
# NODE_EXTRA_CA_CERTS=/etc/ssl/certs/complete-ca-bundle.crt
# GIT_SSL_CAINFO=/etc/ssl/certs/complete-ca-bundle.crt

# Test połączenia z Terraform Registry (przez proxy)
curl -v https://registry.terraform.io/.well-known/terraform.json

# Powinna być odpowiedź 200 OK bez błędów certyfikatu

# Test Terraform init (w dowolnym katalogu z .tf)
terraform init
```

## Rozwiązywanie problemów

### Docker nie może pobrać obrazu bazowego

```
Error: failed to solve: failed to fetch
```

**Rozwiązanie:** Upewnij się że masz dostęp do internetu i Docker Desktop jest uruchomiony.

### Nie można zalogować do ACR

```
Error: unauthorized: authentication required
```

**Rozwiązanie:** Sprawdź czy:
- Masz dostęp do sieci Azure przez VPN (opcja A)
- Token jest ważny i nie wygasł (opcja B)

### Nie można skopiować certyfikatów podczas budowania

```
Error: COPY failed: file not found
```

**Rozwiązanie:** Upewnij się że:
- Uruchamiasz docker build z katalogu `docker/runner-image/`
- Katalog `../../certificates/` istnieje i zawiera wszystkie certyfikaty

### Obraz został wypchnięty ale Terraform nie widzi nowej wersji

**Rozwiązanie:**
1. Sprawdź czy zacommitowałeś i wypchnąłeś zmianę w `devops_arc_runner.tf`
2. Sprawdź GitHub Actions - czy workflow się wykonał
3. Sprawdź logi Terraform apply w GitHub Actions

## Dodatkowe informacje

### Struktura bundle certyfikatów

Dockerfile tworzy plik `/etc/ssl/certs/complete-ca-bundle.crt` zawierający:

1. **Mozilla CA bundle** (146 certyfikatów) - z `/etc/ssl/certs/ca-certificates.crt`
2. **Pekao Root CA** - główny certyfikat CA Pekao
3. **Pekao Level 2 CA** - pośredni certyfikat CA
4. **GitHub Enterprise Server** - certyfikat serwera GitHub
5. **Proxy Intermediate CA** - certyfikat proxy SSL intercepting

Ten kompletny bundle umożliwia weryfikację:
- ✅ Standardowych serwisów publicznych (npm, PyPI, itp.)
- ✅ Terraform Registry (przez proxy)
- ✅ GitHub Enterprise Server
- ✅ Azure Services

### Częstotliwość aktualizacji

Certyfikaty mają ograniczoną ważność. Sprawdzaj daty wygaśnięcia:

```bash
# Proxy CA
openssl x509 -in ../../certificates/proxy-intermediate-ca.crt -noout -dates

# Inne certyfikaty
openssl x509 -in ../../certificates/pekao-root-ca.crt -noout -dates
```

Gdy certyfikat proxy zbliża się do daty wygaśnięcia:
1. Wyciągnij nowy certyfikat z działającego runnera
2. Zaktualizuj plik `certificates/proxy-intermediate-ca.crt`
3. Zbuduj i wypchnij nowy obraz
4. Zaktualizuj wersję w Terraform
