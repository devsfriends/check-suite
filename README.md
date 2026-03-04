# Protótipo: Webhook de Check Suite com GitHub App

Este repositório documenta um protótipo de aplicação que recebe eventos `check_suite` via webhook e cria/atualiza `check_run` no GitHub.

## Objetivo

Criar uma aplicação que:

- exponha a URL `POST /webhook`
- receba eventos de `check_suite`
- autentique como GitHub App usando `App ID + Installation ID + Private Key`
- crie/atualize/finalize check runs via API do GitHub

## Fluxo do protótipo

1. GitHub dispara webhook `check_suite` para `https://SEU_DOMINIO/webhook`.
2. A aplicação valida assinatura (`X-Hub-Signature-256`) e parseia payload.
3. A aplicação gera token de instalação do GitHub App.
4. A aplicação usa o token para chamar API de Check Runs.
5. O status aparece na aba **Checks** do PR/commit.

## 1) Criar o GitHub App

No GitHub, acesse:

1. `Settings`
2. `Developer settings`
3. `GitHub Apps`
4. `New GitHub App`

Configuração mínima recomendada:

- `GitHub App name`: `check-suite-local` (ou outro nome)
- `Homepage URL`: URL do projeto
- `Webhook URL`: URL pública do seu endpoint (`https://SEU_DOMINIO/webhook`)
- `Webhook active`: habilitado
- `Webhook secret`: obrigatório (use valor forte)

O webhook pode ser configurado já na criação do GitHub App, sem precisar voltar depois apenas para ativá-lo.

### Permissões do app

Baseado no setup deste repositório:

- `Repository permissions > Checks`: **Read & write** (obrigatório)
- `Repository permissions > Metadata`: **Read** (obrigatório, padrão GitHub)
- `Repository permissions > Contents`: **Read** (opcional)

### Eventos do webhook

Marque no GitHub App:

- `check_suite` (obrigatório)
- `check_run` (opcional, útil para debug/observabilidade)

Depois de criar o app:

1. Abra `Settings` do próprio GitHub App.
2. Vá em `Private keys`.
3. Clique em **Generate a private key**.
4. Salve a chave `.pem` em local seguro.

Depois instale o app na organização/repositório alvo.

## 2) Obter as credenciais

Você precisará de três valores:

- `APP_ID`
- `INSTALLATION_ID`
- `PRIVATE_KEY` (`.pem`)

### `APP_ID`

1. Abra a página do seu GitHub App.
2. Na seção **About**, copie o **App ID**.

### `INSTALLATION_ID`

1. Na página do app, clique em **Install App**.
2. Abra a instalação na organização.
3. A URL terá um formato como:
   `https://github.com/organizations/devsfriends/settings/installations/<INSTALLATION_ID>`
4. O número no final da URL é o `INSTALLATION_ID`.

Opcionalmente, esse ID também pode ser consultado via API:

```bash
curl -H "Authorization: Bearer $JWT" \
  https://api.github.com/repos/devsfriends/check-suite/installation | jq .id
```

### `PRIVATE_KEY`

1. Abra o GitHub App.
2. Vá em `Settings > Private keys`.
3. Clique em **Generate a private key**.
4. Salve o arquivo `.pem` em local seguro.

## 3) Configurar credenciais locais

Exemplo de variáveis locais:

```bash
export APP_ID=2981678
export INSTALLATION_ID=113313264
export PRIVATE_KEY=scripts/check-run-test-devfriends.2026-03-01.private-key.pem
```

Gerar token de instalação:

```bash
eval "$(./scripts/create-installation-token.sh \
  --app-id "$APP_ID" \
  --installation-id "$INSTALLATION_ID" \
  --private-key "$PRIVATE_KEY")"
```

O script exporta `INSTALL_TOKEN` (válido por ~1h).

## 4) Testar criação/atualização de check run

```bash
export REPO=devsfriends/check-suite
SHA=$(git rev-parse --verify HEAD)

./scripts/check-run.sh create \
  --name "My Local Check" \
  --sha "$SHA" \
  --repo "$REPO"

./scripts/check-run.sh update \
  --id <CHECK_RUN_ID> \
  --status in_progress \
  --repo "$REPO"

./scripts/check-run.sh complete \
  --id <CHECK_RUN_ID> \
  --conclusion success \
  --summary "All checks passed" \
  --repo "$REPO"
```

## 5) Fluxo completo de exemplo

```bash
# 1. Gere o token (válido por ~1 hora)
eval "$(./scripts/create-installation-token.sh \
  --app-id "$APP_ID" \
  --installation-id "$INSTALLATION_ID" \
  --private-key "$PRIVATE_KEY")"

# 2. Configure variáveis
export REPO=devsfriends/check-suite
SHA=$(git rev-parse --verify HEAD)

# 3. Crie um check run
CHECK_RUN_ID=$(./scripts/check-run.sh create \
  --name "My Test" \
  --sha "$SHA" \
  --repo "$REPO" | grep CHECK_RUN_ID | cut -d= -f2)

echo "Check Run ID: $CHECK_RUN_ID"

# 4. Atualize para in_progress
./scripts/check-run.sh update \
  --id "$CHECK_RUN_ID" \
  --status in_progress \
  --repo "$REPO"

# 5. Complete com sucesso
./scripts/check-run.sh complete \
  --id "$CHECK_RUN_ID" \
  --conclusion success \
  --summary "Check passed without issues" \
  --repo "$REPO"
```

## 6) Status possíveis de Check Run

### `status` (estado de execução)

| status | Quando usar |
|---|---|
| `queued` | Job criado e aguardando execução |
| `in_progress` | Job em execução |
| `completed` | Job finalizado (exige `conclusion`) |

Regras práticas:

- Criação: normalmente começar com `queued`
- Durante processamento: atualizar para `in_progress`
- Ao terminar: atualizar para `completed` + `conclusion`

### `conclusion` (resultado final, só com `status=completed`)

| conclusion | Quando usar |
|---|---|
| `success` | Execução OK, sem erros |
| `failure` | Execução terminou com erro |
| `neutral` | Sem impacto positivo/negativo |
| `cancelled` | Execução cancelada |
| `timed_out` | Execução excedeu tempo |
| `action_required` | Precisa de ação manual externa |
| `skipped` | Execução ignorada por regra |
| `stale` | Resultado antigo/obsoleto |

## 7) Mapeamento simples de eventos `check_suite`

Sugestão para o webhook:

- `action = requested` ou `rerequested`:
  - criar novo `check_run` com `status=queued`
  - atualizar para `in_progress` quando iniciar processamento
- `action = completed`:
  - opcionalmente apenas registrar observabilidade
  - ou reconciliar estado local com a conclusão recebida

Arquivos de payload de referência neste repositório:

- `payload-success.json`
- `payload-failure.json`

## 8) Troubleshooting

### Erro: "You must authenticate via a GitHub App"

- Verifique se está usando `INSTALL_TOKEN` gerado por `create-installation-token.sh`, e não um PAT.
- Confirme que o app está instalado na organização ou no repositório.

### Erro: "Installation not found"

- Verifique o `INSTALLATION_ID`.
- Confirme no GitHub App se a instalação realmente existe.

### Erro: "Not Found"

- Verifique o valor de `REPO` no formato `owner/repo`.
- Confirme que o repositório existe e está acessível para a instalação do app.

### Token expirado

- O token de instalação expira em cerca de 1 hora.
- Gere um novo token executando `create-installation-token.sh` novamente.

## 9) Segurança

Nunca versionar:

- private key (`.pem`)
- `INSTALL_TOKEN`
- segredo de webhook

Recomendado:

- validar assinatura HMAC SHA-256 (`X-Hub-Signature-256`)
- rotacionar segredo do webhook
- renovar token de instalação periodicamente (expira)

Exemplo de `.env` local não versionado:

```bash
export APP_ID=2981678
export INSTALLATION_ID=113313264
export PRIVATE_KEY=scripts/check-run-test-devfriends.2026-03-01.private-key.pem
```

Carregando e gerando token:

```bash
source .env
eval "$(./scripts/create-installation-token.sh \
  --app-id "$APP_ID" \
  --installation-id "$INSTALLATION_ID" \
  --private-key "$PRIVATE_KEY")"
```

## Referências

- [Check Runs API](https://docs.github.com/en/rest/checks/runs)
- [Webhook events and payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
