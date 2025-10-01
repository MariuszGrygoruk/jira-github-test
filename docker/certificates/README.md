# Certyfikaty SSL dla GitHub Actions Runner

Ten katalog zawiera wszystkie certyfikaty SSL potrzebne do poprawnej weryfikacji połączeń w środowisku Pekao.

## Zawartość katalogu

| Plik | Opis | Ważność do |
|------|------|------------|
| `pekao-root-ca.crt` | Certyfikat główny CA Pekao (Root CA II) | 2034-06-03 |
| `pekao-level2.crt` | Certyfikat pośredni CA (Level 2) | 2030-02-23 |
| `github-server.crt` | Certyfikat serwera GitHub Enterprise | 2027-04-24 |
| `proxy-intermediate-ca.crt` | Certyfikat pośredni CA proxy (SSL intercepting) | 2027-01-21 |

## Sprawdzenie ważności certyfikatów

```bash
# Proxy CA (najczęściej wymaga aktualizacji)
openssl x509 -in proxy-intermediate-ca.crt -noout -dates

# Root CA
openssl x509 -in pekao-root-ca.crt -noout -dates

# Level 2 CA
openssl x509 -in pekao-level2.crt -noout -dates

# GitHub Server
openssl x509 -in github-server.crt -noout -dates
```

## Certyfikat proxy (SSL intercepting)

### Co to jest?

Pekao używa SSL intercepting proxy (`proxyx.cn.in.pekao.com.pl:8080`), które:
1. Przechwytuje wszystkie połączenia HTTPS wychodzące
2. Podmienia certyfikaty serwerów zewnętrznych na własne
3. Własne certyfikaty są podpisane przez **Departament Cyberbezpieczeństwa CA**

### Dlaczego jest potrzebny?

Bez tego certyfikatu połączenia do zewnętrznych serwisów (np. `registry.terraform.io`) kończą się błędem weryfikacji SSL:

```
Error: certificate verify failed
```

### Jak zaktualizować gdy wygaśnie?

1. **Połącz się z działającym runnerem:**

```bash
kubectl exec -it <runner-pod-name> -n actions-runner-system -- bash
```

2. **Wyciągnij certyfikat proxy:**

```bash
# Metoda 1: Przez połączenie SSL z zewnętrznym serwisem
openssl s_client -connect registry.terraform.io:443 \
  -proxy proxyx.cn.in.pekao.com.pl:8080 -showcerts 2>/dev/null </dev/null | \
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' | \
  awk 'BEGIN {cert=0} /BEGIN CERTIFICATE/ {cert++} cert==2 {print}'

# Metoda 2: Bezpośrednio z proxy (jeśli dostępne)
openssl s_client -connect proxyx.cn.in.pekao.com.pl:8080 -showcerts 2>/dev/null </dev/null
```

3. **Zastąp plik `proxy-intermediate-ca.crt`:**

Skopiuj wynik (od `-----BEGIN CERTIFICATE-----` do `-----END CERTIFICATE-----`) i zapisz w tym pliku.

4. **Zbuduj nowy obraz Docker:**

Zobacz instrukcje w: `docker/runner-image/BUILD-EXTERNAL.md`

## Struktura łańcucha certyfikatów

```
Pekao SA Root CA II (pekao-root-ca.crt)
    │
    ├─> Pekao SA Level 2 (pekao-level2.crt)
    │       │
    │       ├─> GitHub Server (github-server.crt)
    │       │
    │       └─> Proxy Intermediate CA (proxy-intermediate-ca.crt)
    │               │
    │               └─> Podmieniane certyfikaty zewnętrznych serwisów
    │                   (registry.terraform.io, releases.hashicorp.com, itp.)
```

## Użycie w Dockerfile

Wszystkie certyfikaty z tego katalogu są kopiowane do obrazu Docker i łączone z Mozilla CA bundle:

```dockerfile
# docker/runner-image/Dockerfile
COPY ../../certificates/*.crt /tmp/certs/

RUN cat /etc/ssl/certs/ca-certificates.crt \
        /tmp/certs/pekao-root-ca.crt \
        /tmp/certs/pekao-level2.crt \
        /tmp/certs/github-server.crt \
        /tmp/certs/proxy-intermediate-ca.crt \
        > /etc/ssl/certs/complete-ca-bundle.crt
```

Wynikowy plik `/etc/ssl/certs/complete-ca-bundle.crt` zawiera:
- **146 certyfikatów Mozilla CA** (standardowe publiczne CA)
- **4 certyfikaty Pekao** (z tego katalogu)
- **Razem: ~150 certyfikatów**

## Weryfikacja certyfikatów

Sprawdź szczegóły certyfikatu:

```bash
# Pokaż cały certyfikat
openssl x509 -in proxy-intermediate-ca.crt -text -noout

# Pokaż tylko najważniejsze informacje
openssl x509 -in proxy-intermediate-ca.crt -noout -subject -issuer -dates

# Przykładowy output:
# subject=C=PL, ST=mazowieckie, L=Warszawa, O=Bank Pekao S.A., OU=Departament Cyberbezpieczeństwa, CN=Bank Pekao S.A.
# issuer=C=PL, O=Bank Pekao S.A., CN=Pekao SA Level 2
# notBefore=Jan 21 10:50:37 2025 GMT
# notAfter=Jan 21 10:50:37 2027 GMT
```

## Bezpieczeństwo

⚠️ **WAŻNE:**
- Certyfikaty w tym katalogu są **publicznymi certyfikatami CA** (nie zawierają kluczy prywatnych)
- Są bezpieczne do przechowywania w repozytorium Git
- Mogą być dystrybuowane publicznie
- **NIE zawierają żadnych sekretów**

Jedynym wrażliwym plikiem byłby klucz prywatny (`.key`), którego tutaj **nie ma** i **nie powinno być**.

## Troubleshooting

### Problem: Terraform init kończy się błędem certyfikatu

```
Error: Failed to query available provider packages
Error: certificate signed by unknown authority
```

**Przyczyna:** Certyfikat proxy wygasł lub jest niepoprawny.

**Rozwiązanie:** Zaktualizuj `proxy-intermediate-ca.crt` zgodnie z instrukcją powyżej.

### Problem: GitHub Actions kończy się błędem SSL

```
Error: SSL certificate problem: unable to get local issuer certificate
```

**Przyczyna:** Brak certyfikatu GitHub Enterprise w bundle.

**Rozwiązanie:** Sprawdź czy `github-server.crt` jest poprawny i nie wygasł.

### Problem: npm/pip/curl nie może połączyć się z zewnętrznymi serwisami

```
Error: SSL certificate verify failed
```

**Przyczyna:** Połączenie przez proxy wymaga certyfikatu proxy CA.

**Rozwiązanie:**
1. Sprawdź czy `proxy-intermediate-ca.crt` jest aktualny
2. Sprawdź czy `NO_PROXY` w Helm values nie blokuje połączenia
3. Zbuduj nowy obraz z aktualnymi certyfikatami
