# Contribuindo com o Jojô Guest

Obrigado por dedicar tempo para contribuir! Este documento descreve o fluxo recomendado para colaborar com o projeto.

## Código de Conduta
Ao interagir com o projeto, aceite e respeite o nosso [Código de Conduta](./CODE_OF_CONDUCT.md).

## Como começar
1. Faça um fork do repositório no GitHub.
2. Crie um branch descritivo para cada alteração (`feature/menu-conectividade`, `fix/log-rotation`, etc.).
3. Garanta que a alteração esteja coberta por testes ou documentação apropriada.
4. Abra um Pull Request descrevendo claramente o problema resolvido ou a funcionalidade adicionada.

## Diretrizes de desenvolvimento
- **Bash**
  - Utilize `bash` posix com `set -euo pipefail` quando possível (o script principal já gerencia erros).
  - Ao adicionar novas funções, documente-as dentro do script com comentários sucintos.
  - Execute `bash -n jojo-guest.sh` e, se disponível, `shellcheck jojo-guest.sh` antes de enviar o PR.
- **Python**
  - Evite depender de ambientes virtuais; o projeto instala pacotes globalmente com `--break-system-packages`.
  - Utilize tipagem estática sempre que possível e mantenha imports agrupados por padrão (`stdlib`, `third-party`, `local`).
  - Testes locais podem ser disparados com `python3 app/jojo_guest.py --dry-run` após materializar o script via menu de instalação.

## Documentação
- Atualize o [README](./README.md) sempre que introduzir um novo recurso ou parâmetro CLI.
- Inclua exemplos de uso ou mudanças no fluxo operacional.

## Commit messages
- Use mensagens claras no formato imperativo curto: `Add cron scheduler helper`, `Fix WhatsApp provision`.
- Separe commits lógicos; evite misturar refatorações com correções.

## Pull Requests
- Preencha o template padrão fornecido em `.github/pull_request_template.md`.
- Inclua resultados de testes ou validações relevantes na seção de checklist.
- Aguarde a revisão antes de realizar merge.

Agradecemos por contribuir para tornar o Jojô Guest ainda melhor!
