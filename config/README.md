# Arquivos de configuração do Jojô Guest

Este diretório é criado automaticamente pelo script `jojo-guest.sh` durante a instalação em produção. Os arquivos são mantidos fora do controle de versão para evitar exposição de credenciais.

## Arquivos gerados
- `jojo-guest.env`: variáveis de ambiente com credenciais da Assessoria VIP, SMTP, WhatsApp e integrações opcionais.
- `google_service_account.json`: credenciais de conta de serviço Google (opcional para integração com Sheets).

Ao clonar o repositório, você **não** precisa criar esses arquivos manualmente. Eles serão gerados pelo instalador com placeholders e podem ser editados via menu **2) Conectividade**.
