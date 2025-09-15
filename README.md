# Jojô Guest

Automação oficial para o fluxo de convites do portal [Assessoria VIP](https://assessoriavip.com.br). O projeto combina uma camada Bash para gestão completa da instalação e orquestração do serviço com uma camada Python baseada em Playwright para executar o fluxo web, enviar mensagens pelo WhatsApp Web e manter logs, backups, capturas de tela e alertas por e-mail.

> **Importante:** todo o comportamento descrito abaixo é entregue por um único arquivo executável [`jojo-guest.sh`](./jojo-guest.sh). Nenhuma outra dependência específica do repositório é necessária para executar a automação em produção.

## Sumário
- [Recursos principais](#recursos-principais)
- [Estrutura de diretórios](#estrutura-de-diretórios)
- [Pré-requisitos do sistema](#pré-requisitos-do-sistema)
- [Instalação](#instalação)
- [Configuração de conectividade](#configuração-de-conectividade)
- [Execução manual e por linha de comando](#execução-manual-e-por-linha-de-comando)
- [Programação via cron](#programação-via-cron)
- [Logs, backups e screenshots](#logs-backups-e-screenshots)
- [Atualização](#atualização)
- [Desinstalação](#desinstalação)
- [Diretrizes de contribuição](#diretrizes-de-contribuição)
- [Segurança](#segurança)
- [Licença](#licença)

## Recursos principais
- **Instalador único:** detecta Ubuntu Server 24.04+, instala todos os pacotes APT e bibliotecas Python necessárias (Playwright, Pydantic, Google APIs, etc.) e prepara a árvore `/opt/jojo-guest` com as permissões corretas.
- **Automação Playwright completa:** autentica na Assessoria VIP, percorre eventos "Em andamento", aplica filtros "Não enviados" e dispara mensagens via WhatsApp Web com contexto persistente (`state/whatsapp`).
- **Gerenciamento operacional:** menu visual (tput/cores) com instalação, conectividade, execução pontual, agendamentos cron, rotação de logs, backups, atualização e desinstalação.
- **Tratamento de erros:** logs detalhados com até 10 arquivos por rotação, evidências em `screenshots/<EVENT_ID>` (10 mais recentes) e alerta automático por SMTP em falhas não tratadas.
- **Configuração isolada:** credenciais armazenadas em `config/jojo-guest.env` e, quando aplicável, `config/google_service_account.json`.

## Estrutura de diretórios
Após a instalação a seguinte estrutura é criada em `/opt/jojo-guest`:

```
/opt/jojo-guest
├── app/               # Código Python (Playwright) materializado pelo script
├── bin/               # Utilidades auxiliares criadas pelo instalador
├── config/            # Arquivos .env e credenciais
├── logs/              # Logs rotacionados (máx. 10)
├── repo/              # Clonagem opcional do repositório de referência (https://github.com/aryabdo/guest-list)
├── screenshots/       # Evidências por evento (máx. 10 por ID)
├── state/             # Contextos persistentes do navegador (ex.: WhatsApp)
├── tmp/               # Arquivos temporários e backups gerados
└── jojo-guest.sh      # Script principal (se copiado para o diretório)
```

## Pré-requisitos do sistema
- Ubuntu Server 24.04 LTS ou superior.
- Acesso com privilégios de `sudo` para instalar pacotes APT e bibliotecas Python globais.
- Acesso à internet para baixar dependências, Playwright Chromium e clonar o repositório opcional.

## Instalação
1. Copie o arquivo [`jojo-guest.sh`](./jojo-guest.sh) para o servidor destino (ex.: via `scp`).
2. Conceda permissão de execução: `chmod +x jojo-guest.sh`.
3. Execute o instalador e siga o menu visual:
   ```bash
   sudo ./jojo-guest.sh
   ```
4. Escolha a opção **1) Instalação Geral**. O processo irá:
   - Garantir que o sistema é compatível (Ubuntu 24.04+).
   - Instalar e/ou atualizar pacotes APT obrigatórios.
   - Instalar bibliotecas Python globalmente com `pip3 --break-system-packages`.
   - Executar `python3 -m playwright install --with-deps chromium`.
   - Criar diretórios, arquivos de configuração e materializar `app/jojo_guest.py` via heredoc.

Após a conclusão, utilize o menu para preencher credenciais antes de executar o fluxo automático.

## Configuração de conectividade
A opção **2) Conectividade** do menu principal permite editar `config/jojo-guest.env` e preparar integrações:
- **Assessoria VIP:** e-mail e senha utilizados no login do portal.
- **WhatsApp Web:** provisionamento de sessão persistente (`state/whatsapp`). O script executa o Playwright em modo headful temporariamente para leitura do QR Code.
- **Google Sheets (opcional):** IDs de planilhas e credenciais em `config/google_service_account.json`.
- **SMTP:** servidor, porta, credenciais e destinatários padrão para alertas de erro.

Os valores são armazenados diretamente no `.env` e podem ser ajustados a qualquer momento via menu.

## Execução manual e por linha de comando
- Pelo menu, selecione **3) Executar Agora** para processar convites pendentes imediatamente.
- Para execução direta via CLI (útil em automações externas), utilize:
  ```bash
  ./jojo-guest.sh --run              # Executa o fluxo completo em modo headless
  ./jojo-guest.sh --run --headful    # Executa com navegador visível
  ./jojo-guest.sh --run --dry-run    # Apenas simula as ações (sem envios)
  ./jojo-guest.sh --run --event-id <ID>  # Processa apenas um evento específico
  ```

A camada Python registra logs em `logs/jojo-guest-YYYYmmdd-HHMMSS.log` e remove temporários de `tmp/` ao final.

## Programação via cron
A opção **4) Programação (cron)** permite agendar execuções recorrentes (diária, semanal ou mensal) do comando `jojo-guest.sh --run`. As entradas ficam no `crontab` do usuário atual (ou `root`, quando executado com sudo) e são identificadas pelo comentário `# jojo-guest`. O menu também lista e remove agendamentos existentes do próprio aplicativo.

## Logs, backups e screenshots
- **Logs:** a opção **5) Logs & Backups** permite visualizar o arquivo mais recente, rotacionar os logs (mantendo apenas os 10 últimos) e gerar um pacote de backup (`tmp/backup-YYYYmmdd-HHMMSS.tar.gz`) com `config/` e `logs/`.
- **Screenshots:** após finalizar cada evento, a automação salva uma imagem em `screenshots/<EVENT_ID>/`. Se o diretório exceder 10 arquivos, os mais antigos são removidos.

## Atualização
Utilize a opção **6) Atualizar** para:
1. Remover binários e artefatos do diretório `app/` (mantendo `config/`, `logs/`, `state/`, `screenshots/`).
2. Reinstalar dependências e materializar o código Python atualizado.
3. Clonar ou atualizar (`git pull`) o repositório de referência em `/opt/jojo-guest/repo`.
4. Reiniciar o fluxo principal automaticamente ao término.

## Desinstalação
A opção **7) Desinstalar** remove completamente `/opt/jojo-guest`, incluindo agendamentos cron marcados como `# jojo-guest`. Uma confirmação digitando `SIM` é exigida antes da remoção. Nenhum outro aplicativo do servidor é afetado.

## Diretrizes de contribuição
Contribuições são bem-vindas! Leia o arquivo [CONTRIBUTING.md](./CONTRIBUTING.md) para orientações sobre estilo de código, abertura de issues e processo de pull request. Templates específicos estão disponíveis em `.github/` para facilitar relatos de bugs e sugestões.

## Segurança
Relate vulnerabilidades seguindo as instruções em [SECURITY.md](./SECURITY.md). Não abra issues públicas para informações sensíveis.

## Licença
Este projeto é licenciado sob os termos da [Licença MIT](./LICENSE).
