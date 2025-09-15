#!/usr/bin/env bash

VERSION="0.1.0"
APP_NAME="Jojô Guest"
BASE_DIR="/opt/jojo-guest"
BIN_DIR="${BASE_DIR}/bin"
APP_DIR="${BASE_DIR}/app"
CONFIG_DIR="${BASE_DIR}/config"
LOG_DIR="${BASE_DIR}/logs"
SCREENSHOT_DIR="${BASE_DIR}/screenshots"
STATE_DIR="${BASE_DIR}/state"
TMP_DIR="${BASE_DIR}/tmp"
REPO_DIR="${BASE_DIR}/repo"
ENV_FILE="${CONFIG_DIR}/jojo-guest.env"
PYTHON_FILE="${APP_DIR}/jojo_guest.py"
SERVICE_ACCOUNT_FILE="${CONFIG_DIR}/google_service_account.json"
REPO_URL="https://github.com/aryabdo/guest-list"
MAX_LOGS=10
MAX_SCREENSHOTS=10

APT_PACKAGES=(
  "python3"
  "python3-pip"
  "git"
  "curl"
  "wget"
  "unzip"
  "jq"
  "cron"
  "libnss3"
  "libatk-bridge2.0-0"
  "libxkbcommon0"
  "libxcomposite1"
  "libxrandr2"
  "libxi6"
  "libxcursor1"
  "libxdamage1"
  "libgbm1"
  "libasound2"
  "fonts-liberation"
  "libatk1.0-0"
  "libdrm2"
  "libxfixes3"
)

PIP_PACKAGES=(
  "playwright"
  "pydantic"
  "python-dotenv"
  "gspread"
  "google-auth"
  "tenacity"
)

if [ -n "$SUDO_USER" ]; then
  CURRENT_USER="$SUDO_USER"
  CURRENT_GROUP="$(id -gn "$SUDO_USER")"
else
  CURRENT_USER="$(id -un)"
  CURRENT_GROUP="$(id -gn)"
fi

if command -v tput >/dev/null 2>&1; then
  COLOR_PRIMARY="$(tput setaf 6)"
  COLOR_SECONDARY="$(tput setaf 2)"
  COLOR_WARNING="$(tput setaf 3)"
  COLOR_ERROR="$(tput setaf 1)"
  STYLE_BOLD="$(tput bold)"
  STYLE_RESET="$(tput sgr0)"
else
  COLOR_PRIMARY=""
  COLOR_SECONDARY=""
  COLOR_WARNING=""
  COLOR_ERROR=""
  STYLE_BOLD=""
  STYLE_RESET=""
fi

print_header() {
  clear
  cat <<'ART'
      _       _        _      ____                 _   
     | | ___ (_) ___  | |_   / ___| ___   ___  ___| |_ 
  _  | |/ _ \| |/ _ \ | __| | |  _ / _ \ / _ \/ __| __|
 | |_| | (_) | |  __/ | |_  | |_| | (_) |  __/ (__| |_ 
  \___/ \___// |\___|  \__|  \____|\___/ \___|\___|\__|
           |__/                                         
ART
  printf "%s%s v%s%s\n" "$STYLE_BOLD" "$APP_NAME" "$VERSION" "$STYLE_RESET"
  echo
}

pause_return() {
  echo
  read -rp "Pressione Enter para voltar ao menu..." _
}

ensure_os() {
  if [ ! -f /etc/os-release ]; then
    echo "${COLOR_ERROR}Sistema operacional não identificado.${STYLE_RESET}" >&2
    exit 1
  fi
  . /etc/os-release
  if [ "${ID}" != "ubuntu" ]; then
    echo "${COLOR_ERROR}Este instalador suporta apenas Ubuntu.${STYLE_RESET}" >&2
    exit 1
  fi
  VERSION_ID_NUM=${VERSION_ID%%.*}
  if [ "$VERSION_ID_NUM" -lt 24 ]; then
    echo "${COLOR_ERROR}Ubuntu 24.04 ou superior é obrigatório.${STYLE_RESET}" >&2
    exit 1
  fi
}

with_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_dependencies() {
  ensure_os
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Instalando dependências do sistema...${STYLE_RESET}"
  with_sudo apt-get update -y
  with_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
}

install_python_dependencies() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Instalando dependências Python...${STYLE_RESET}"
  for pkg in "${PIP_PACKAGES[@]}"; do
    with_sudo pip3 install --upgrade --break-system-packages "$pkg"
  done
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Preparando Playwright...${STYLE_RESET}"
  with_sudo python3 -m playwright install --with-deps chromium
}

create_directories() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Preparando diretórios em ${BASE_DIR}...${STYLE_RESET}"
  for dir in "$BASE_DIR" "$BIN_DIR" "$APP_DIR" "$CONFIG_DIR" "$LOG_DIR" \
             "$SCREENSHOT_DIR" "$STATE_DIR" "$TMP_DIR" "$REPO_DIR"; do
    with_sudo mkdir -p "$dir"
  done
  with_sudo chmod -R 775 "$BASE_DIR"
  with_sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$BASE_DIR"
  with_sudo mkdir -p "${STATE_DIR}/whatsapp"
}

materialize_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    cat <<'ENV' | with_sudo tee "$ENV_FILE" >/dev/null
# Configuração principal do Jojô Guest
ASSESSORIA_VIP_EMAIL=
ASSESSORIA_VIP_PASSWORD=
WHATSAPP_PROVISIONED=false
GOOGLE_SHEETS_IDS=
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM=
SMTP_TO=
SMTP_USE_TLS=true
SMTP_USE_SSL=false
DEFAULT_DRY_RUN=false
ENVIRONMENT=production
ENV
  fi
  with_sudo chmod 660 "$ENV_FILE"
}

materialize_google_placeholder() {
  if [ ! -f "$SERVICE_ACCOUNT_FILE" ]; then
    cat <<'JSON' | with_sudo tee "$SERVICE_ACCOUNT_FILE" >/dev/null
{
  "type": "service_account",
  "project_id": "preencha",
  "private_key_id": "preencha",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "preencha@preencha.iam.gserviceaccount.com",
  "client_id": "preencha",
  "token_uri": "https://oauth2.googleapis.com/token",
  "universe_domain": "googleapis.com",
  "_comment": "Substitua este arquivo pelas credenciais reais da sua Service Account"
}
JSON
  fi
  with_sudo chmod 660 "$SERVICE_ACCOUNT_FILE"
}

set_env_var() {
  local key="$1" value="$2"
  with_sudo touch "$ENV_FILE"
  local escaped
  escaped=$(printf '%s' "$value" | sed 's/[\\&/]/\\\\&/g')
  if grep -q "^${key}=" "$ENV_FILE"; then
    with_sudo sed -i "s|^${key}=.*|${key}=${escaped}|" "$ENV_FILE"
  else
    echo "${key}=${value}" | with_sudo tee -a "$ENV_FILE" >/dev/null
  fi
}

get_env_var() {
  local key="$1"
  if [ -f "$ENV_FILE" ]; then
    local val
    val=$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 | cut -d'=' -f2-)
    echo "$val"
  fi
}

materialize_python_module() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Gerando módulo Python...${STYLE_RESET}"
  cat <<'PY' | with_sudo tee "$PYTHON_FILE" >/dev/null
#!/usr/bin/env python3
"""Fluxo automatizado do Jojô Guest."""
import argparse
import logging
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from dotenv import load_dotenv
from pydantic import BaseSettings, Field, validator
from playwright.sync_api import BrowserContext, Page, TimeoutError as PlaywrightTimeoutError, sync_playwright
from tenacity import retry, stop_after_attempt, wait_fixed
import smtplib
import ssl
import traceback

BASE_DIR = Path("/opt/jojo-guest")
CONFIG_DIR = BASE_DIR / "config"
LOG_DIR = BASE_DIR / "logs"
SCREENSHOT_DIR = BASE_DIR / "screenshots"
STATE_DIR = BASE_DIR / "state"
TMP_DIR = BASE_DIR / "tmp"
ENV_FILE = CONFIG_DIR / "jojo-guest.env"
MAX_LOGS = 10
MAX_SCREENSHOTS = 10


class AppConfig(BaseSettings):
    assessoria_email: str = Field("", alias="ASSESSORIA_VIP_EMAIL")
    assessoria_password: str = Field("", alias="ASSESSORIA_VIP_PASSWORD")
    whatsapp_provisioned: bool = Field(False, alias="WHATSAPP_PROVISIONED")
    google_sheets_ids: str = Field("", alias="GOOGLE_SHEETS_IDS")
    smtp_host: str = Field("", alias="SMTP_HOST")
    smtp_port: int = Field(587, alias="SMTP_PORT")
    smtp_username: str = Field("", alias="SMTP_USERNAME")
    smtp_password: str = Field("", alias="SMTP_PASSWORD")
    smtp_from: str = Field("", alias="SMTP_FROM")
    smtp_to: str = Field("", alias="SMTP_TO")
    smtp_use_tls: bool = Field(True, alias="SMTP_USE_TLS")
    smtp_use_ssl: bool = Field(False, alias="SMTP_USE_SSL")
    default_dry_run: bool = Field(False, alias="DEFAULT_DRY_RUN")
    environment: str = Field("production", alias="ENVIRONMENT")

    class Config:
        env_file = str(ENV_FILE)
        env_file_encoding = "utf-8"
        case_sensitive = False

    @validator("smtp_to")
    def sanitize_smtp_to(cls, v: str) -> str:
        return ",".join([item.strip() for item in v.split(",") if item.strip()])

    @property
    def smtp_recipients(self) -> List[str]:
        return [item for item in self.smtp_to.split(",") if item]


def rotate_logs() -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logs = sorted(LOG_DIR.glob("jojo-guest-*.log"))
    while len(logs) >= MAX_LOGS:
        old = logs.pop(0)
        try:
            old.unlink()
        except OSError:
            pass
    log_path = LOG_DIR / f"jojo-guest-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.log"
    return log_path


def setup_logging() -> Path:
    log_path = rotate_logs()
    handlers = [logging.FileHandler(log_path, encoding="utf-8"), logging.StreamHandler(sys.stdout)]
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=handlers,
    )
    logging.getLogger("playwright").setLevel(logging.WARNING)
    return log_path


def email_on_error(config: AppConfig, log_path: Path, error: Exception, event_id: Optional[str]) -> None:
    if not config.smtp_host or not config.smtp_recipients:
        return
    subject = f"[Jojô Guest][ERRO] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    if event_id:
        subject += f" {event_id}"
    body = [
        "Olá,",
        "",
        "Um erro não tratado ocorreu durante a execução do Jojô Guest.",
        f"Erro: {error}",
        f"Arquivo de log: {log_path}",
        "Considere revisar as credenciais e reexecutar o fluxo.",
        "",
        "--",
        "Jojô Guest",
    ]
    message = f"Subject: {subject}\nFrom: {config.smtp_from}\nTo: {', '.join(config.smtp_recipients)}\n\n" + "\n".join(body)
    try:
        if config.smtp_use_ssl:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, context=context) as server:
                if config.smtp_username:
                    server.login(config.smtp_username, config.smtp_password)
                server.sendmail(config.smtp_from, config.smtp_recipients, message)
        else:
            with smtplib.SMTP(config.smtp_host, config.smtp_port) as server:
                server.ehlo()
                if config.smtp_use_tls:
                    context = ssl.create_default_context()
                    server.starttls(context=context)
                if config.smtp_username:
                    server.login(config.smtp_username, config.smtp_password)
                server.sendmail(config.smtp_from, config.smtp_recipients, message)
        logging.info("E-mail de alerta enviado para %s", config.smtp_recipients)
    except Exception as email_error:
        logging.error("Falha ao enviar e-mail de alerta: %s", email_error)


class BrowserManager:
    def __init__(self, config: AppConfig, headless: bool = True):
        self.config = config
        self.headless = headless
        self.playwright = None
        self.vip_browser = None
        self.vip_context: Optional[BrowserContext] = None
        self.vip_page: Optional[Page] = None
        self._whatsapp_context: Optional[BrowserContext] = None

    def __enter__(self):
        self.playwright = sync_playwright().start()
        browser_args = ["--disable-dev-shm-usage", "--start-maximized"]
        self.vip_browser = self.playwright.chromium.launch(headless=self.headless, args=browser_args)
        self.vip_context = self.vip_browser.new_context(viewport={"width": 1280, "height": 720})
        self.vip_page = self.vip_context.new_page()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.vip_context:
            self.vip_context.close()
        if self.vip_browser:
            self.vip_browser.close()
        if self._whatsapp_context:
            try:
                self._whatsapp_context.close()
            except Exception:
                pass
        if self.playwright:
            self.playwright.stop()

    def get_whatsapp_context(self, headless: bool) -> BrowserContext:
        if self.playwright is None:
            raise RuntimeError("Playwright não inicializado")
        if self._whatsapp_context is None or self._whatsapp_context.is_closed():
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            whatsapp_state = STATE_DIR / "whatsapp"
            whatsapp_state.mkdir(parents=True, exist_ok=True)
            self._whatsapp_context = self.playwright.chromium.launch_persistent_context(
                user_data_dir=str(whatsapp_state),
                headless=headless,
                viewport={"width": 1280, "height": 720},
                args=["--start-maximized"],
            )
        return self._whatsapp_context

    def provision_whatsapp(self, headless: bool) -> None:
        context = self.get_whatsapp_context(headless=headless)
        page = context.pages[0] if context.pages else context.new_page()
        page.goto("https://web.whatsapp.com", wait_until="networkidle")
        logging.info("Aguarde a leitura do QR Code e pressione CTRL+C para encerrar.")
        try:
            while True:
                time.sleep(2)
        except KeyboardInterrupt:
            logging.info("Provisionamento de WhatsApp encerrado pelo usuário.")


def wait_safe(page: Page, delay: float) -> None:
    time.sleep(delay)


@retry(stop=stop_after_attempt(3), wait=wait_fixed(2), reraise=True)
def login_assessoria_vip(page: Page, config: AppConfig) -> None:
    logging.info("Acessando Assessoria VIP...")
    page.goto("https://assessoriavip.com.br/login", wait_until="networkidle")
    page.fill("input[data-testid='login-email']", config.assessoria_email)
    page.fill("input[data-testid='login-password']", config.assessoria_password)
    page.click("button[data-testid='login-submit']")
    wait_safe(page, 5)
    page.wait_for_load_state("networkidle")


def open_eventos_em_andamento(page: Page) -> None:
    page.get_by_text("Gestão de Eventos", exact=False).click()
    wait_safe(page, 5)
    page.wait_for_load_state("networkidle")
    tab = page.get_by_text("Em andamento", exact=False)
    tab.click()
    wait_safe(page, 5)


def extract_in_progress_count(page: Page) -> int:
    locator = page.locator("xpath=//span[contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'em andamento')]/following-sibling::span")
    try:
        if locator.count():
            value = locator.first.inner_text().strip()
            return int("".join([c for c in value if c.isdigit()]))
    except Exception:
        pass
    fallback = page.locator("xpath=//span[contains(text(),'Em andamento')]")
    if fallback.count():
        text = fallback.first.inner_text()
        digits = "".join([c for c in text if c.isdigit()])
        if digits:
            return int(digits)
    return 0


def scroll_collect_event_links(page: Page) -> List[str]:
    logging.info("Coletando eventos em andamento...")
    collected: List[str] = []
    previous_len = -1
    stable_iterations = 0
    for _ in range(60):
        links = page.locator("a.item[href*='/gestao_eventos/view2/']")
        hrefs = [link.get_attribute("href") for link in links.element_handles()]
        hrefs = [h for h in hrefs if h]
        for href in hrefs:
            if href not in collected:
                collected.append(href)
        if len(collected) == previous_len:
            stable_iterations += 1
        else:
            stable_iterations = 0
        previous_len = len(collected)
        if stable_iterations >= 3:
            break
        page.mouse.wheel(0, 2000)
        wait_safe(page, 1)
    logging.info("Total de eventos encontrados: %s", len(collected))
    return collected


def extract_event_id(event_url: str) -> str:
    return event_url.rstrip("/").split("/")[-1]


def read_statistics(page: Page) -> None:
    stats = page.locator("xpath=//span[contains(text(),'convite') or contains(text(),'convites')]")
    values = stats.all_inner_texts()
    for value in values:
        logging.info("Estatística: %s", value.strip())


def apply_filter_nao_enviados(page: Page) -> None:
    logging.info("Aplicando filtro 'Não enviados'...")
    page.get_by_role("button", name="Filtro").click()
    wait_safe(page, 1)
    try:
        dropdown = page.locator(".vs__selected")
        dropdown.click()
        option = page.get_by_text("Não enviados", exact=False)
        option.click()
    except PlaywrightTimeoutError:
        logging.warning("Não foi possível selecionar 'Não enviados' na primeira tentativa, tentando novamente...")
        dropdown = page.locator(".vs__selected")
        dropdown.click()
        page.get_by_text("Não enviados", exact=False).click()
    apply_button = page.get_by_role("button", name="Aplicar filtros")
    apply_button.click()
    wait_safe(page, 2)


def parse_pending(page: Page) -> int:
    locator = page.locator("xpath=//span[contains(translate(text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'envio pendente')]")
    if locator.count():
        text = locator.first.inner_text()
        digits = "".join([c for c in text if c.isdigit()])
        if digits:
            return int(digits)
    return 0


def handle_whatsapp_flow(target_url: Optional[str], manager: BrowserManager, headless: bool) -> None:
    if not target_url:
        target_url = "https://api.whatsapp.com"
    whatsapp_context = manager.get_whatsapp_context(headless=headless)
    w_page = whatsapp_context.new_page()
    w_page.goto(target_url, wait_until="domcontentloaded")
    wait_safe(w_page, 2)
    for label in ("Cancelar", "Cancel"):
        try:
            w_page.get_by_role("button", name=label).click()
        except Exception:
            continue
    triggered = False
    for text in ("Iniciar Conversa", "Continue to Chat", "Continuar para o chat"):
        try:
            w_page.get_by_text(text, exact=False).click()
            triggered = True
            break
        except Exception:
            continue
    if not triggered:
        try:
            w_page.get_by_role("link", name="Iniciar Conversa").click()
        except Exception:
            pass
    wait_safe(w_page, 2)
    for text in ("usar o WhatsApp Web", "Use o WhatsApp Web", "Use WhatsApp Web"):
        try:
            w_page.get_by_text(text, exact=False).click()
            break
        except Exception:
            continue
    try:
        w_page.wait_for_url("**web.whatsapp.com**", timeout=30000)
    except PlaywrightTimeoutError:
        logging.warning("WhatsApp Web não carregou completamente.")
    wait_safe(w_page, 10)
    sent = False
    selectors = [
        "[data-testid='compose-btn-send']",
        "button[data-testid='wds-ic-send-filled']",
        "button[aria-label='Enviar']",
        "span[data-icon='send']",
    ]
    for selector in selectors:
        try:
            w_page.locator(selector).first.click()
            sent = True
            break
        except Exception:
            continue
    if not sent:
        try:
            w_page.keyboard.press("Enter")
        except Exception:
            pass
    wait_safe(w_page, 5)
    try:
        w_page.close()
    except Exception:
        pass


def finalize_confirmation(page: Page) -> None:
    wait_safe(page, 2)
    for name in ("Sim", "OK", "Ok"):
        try:
            page.get_by_role("button", name=name).click()
            break
        except Exception:
            continue
    try:
        page.locator("button.swal2-confirm").click()
    except Exception:
        pass
    for name in ("Fechar", "Cancelar"):
        try:
            page.get_by_role("button", name=name).click()
            break
        except Exception:
            continue
    try:
        page.keyboard.press("Escape")
    except Exception:
        pass


def send_whatsapp_for_row(page: Page, row_index: int, manager: BrowserManager, headless: bool, dry_run: bool) -> bool:
    rows = page.locator("table.table.table-hover tbody tr")
    if row_index >= rows.count():
        return False
    row = rows.nth(row_index)
    button = row.locator("button.no-sent").first
    if button.count() == 0:
        return False
    logging.info("Processando linha %s", row_index + 1)
    if dry_run:
        logging.info("[DRY-RUN] Envio simulado para a linha %s", row_index + 1)
        return True
    button.click()
    wait_safe(page, 2)
    modal_send = page.locator("button:has-text(\"Enviar\")").first
    if modal_send.count() == 0:
        logging.warning("Botão 'Enviar' do modal não foi localizado.")
        try:
            page.keyboard.press("Escape")
        except Exception:
            pass
        return False
    popup = None
    target_url = None
    try:
        with page.expect_popup() as popup_info:
            modal_send.click()
        popup = popup_info.value
        popup.wait_for_load_state()
        wait_safe(popup, 2)
        target_url = popup.url
    except Exception as exc:
        logging.error("Não foi possível abrir o WhatsApp a partir do modal: %s", exc)
        try:
            page.keyboard.press("Escape")
        except Exception:
            pass
        return False
    finally:
        if popup is not None:
            try:
                popup.close()
            except Exception:
                pass
    handle_whatsapp_flow(target_url, manager, headless)
    finalize_confirmation(page)
    return True


def process_table(page: Page, manager: BrowserManager, headless: bool, dry_run: bool) -> bool:
    rows = page.locator("table.table.table-hover tbody tr")
    total = rows.count()
    logging.info("Total de linhas encontradas: %s", total)
    processed = False
    for index in range(total):
        try:
            if send_whatsapp_for_row(page, index, manager, headless, dry_run):
                processed = True
        except Exception as row_error:
            logging.error("Falha ao enviar RSVP na linha %s: %s", index + 1, row_error)
            logging.debug(traceback.format_exc())
    return processed


def refresh_and_retry_pendentes(page: Page, manager: BrowserManager, headless: bool, dry_run: bool) -> None:
    for attempt in range(3):
        pendentes = parse_pending(page)
        logging.info("Pendentes restantes (tentativa %s): %s", attempt + 1, pendentes)
        if pendentes <= 0:
            break
        processed = process_table(page, manager, headless, dry_run)
        if not processed:
            logging.info("Nenhum convite pendente encontrado nesta tentativa.")
            break
        wait_safe(page, 5)
        page.reload()
        page.wait_for_load_state("networkidle")
        wait_safe(page, 5)
        apply_filter_nao_enviados(page)
    logging.info("Verificação final de pendências: %s", parse_pending(page))



def screenshot_and_rotate(page: Page, event_id: str) -> None:
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    target_dir = SCREENSHOT_DIR / event_id
    target_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(target_dir.glob("*.png"))
    while len(files) >= MAX_SCREENSHOTS:
        old = files.pop(0)
        try:
            old.unlink()
        except OSError:
            pass
    filename = target_dir / f"{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.png"
    page.screenshot(path=str(filename), full_page=True)
    logging.info("Screenshot salva em %s", filename)


def process_event(manager: BrowserManager, base_page: Page, event_url: str, headless: bool, dry_run: bool) -> None:
    full_url = event_url
    if not full_url.startswith("http"):
        full_url = "https://assessoriavip.com.br" + event_url
    event_id = extract_event_id(full_url)
    logging.info("Processando evento %s", event_id)
    base_page.goto(full_url, wait_until="networkidle")
    wait_safe(base_page, 3)
    base_page.get_by_role("link", name="Acessar convidados").click()
    wait_safe(base_page, 3)
    base_page.get_by_role("link", name="RSVP e Mensagens").click()
    wait_safe(base_page, 3)
    read_statistics(base_page)
    apply_filter_nao_enviados(base_page)
    process_table(base_page, manager, headless, dry_run)
    refresh_and_retry_pendentes(base_page, manager, headless, dry_run)
    screenshot_and_rotate(base_page, event_id)


def cleanup_tmp() -> None:
    if TMP_DIR.exists():
        for item in TMP_DIR.iterdir():
            try:
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
            except Exception:
                pass


def run_flow(args: argparse.Namespace, config: AppConfig, log_path: Path) -> None:
    if not config.assessoria_email or not config.assessoria_password:
        logging.error("Credenciais da Assessoria VIP ausentes. Configure antes de executar.")
        return
    dry_run = args.dry_run or config.default_dry_run
    with BrowserManager(config=config, headless=not args.headful) as manager:
        page = manager.vip_page
        login_assessoria_vip(page, config)
        open_eventos_em_andamento(page)
        expected = extract_in_progress_count(page)
        events = scroll_collect_event_links(page)
        if expected and expected != len(events):
            logging.warning("Número esperado (%s) diferente do coletado (%s)", expected, len(events))
        if args.event_id:
            events = [event for event in events if extract_event_id(event) == args.event_id]
        for event in events:
            try:
                process_event(manager, page, event, headless=not args.headful, dry_run=dry_run)
            except Exception as event_error:
                logging.error("Erro ao processar evento %s: %s", extract_event_id(event), event_error)
                logging.debug(traceback.format_exc())
                email_on_error(config, log_path, event_error, extract_event_id(event))
        cleanup_tmp()


def provision_whatsapp(args: argparse.Namespace, config: AppConfig) -> None:
    with BrowserManager(config=config, headless=False) as manager:
        manager.provision_whatsapp(headless=False)
    logging.info("Provisionamento concluído.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Jojô Guest Automation")
    parser.add_argument("--run", action="store_true", help="Executa o fluxo completo")
    parser.add_argument("--headful", action="store_true", help="Executa com navegador visível")
    parser.add_argument("--dry-run", action="store_true", help="Simula o fluxo sem enviar mensagens")
    parser.add_argument("--event-id", help="Processa apenas o evento informado")
    parser.add_argument("--provision-whatsapp", action="store_true", help="Abre o WhatsApp Web para provisionar sessão")
    args = parser.parse_args()

    load_dotenv(dotenv_path=ENV_FILE, override=False)
    config = AppConfig()
    log_path = setup_logging()
    logging.info("Iniciando Jojô Guest - v%s", os.getenv("VERSION", "0.0.0"))
    try:
        if args.provision_whatsapp:
            provision_whatsapp(args, config)
        elif args.run:
            run_flow(args, config, log_path)
        else:
            logging.info("Nenhuma ação solicitada. Utilize --run ou --provision-whatsapp.")
    except Exception as error:
        logging.error("Erro fatal: %s", error)
        logging.debug(traceback.format_exc())
        email_on_error(config, log_path, error, args.event_id)
        raise
    finally:
        cleanup_tmp()


if __name__ == "__main__":
    main()
PY
  with_sudo chmod 775 "$PYTHON_FILE"
}

materialize_assets() {
  materialize_env_file
  materialize_google_placeholder
  materialize_python_module
}

deploy_self() {
  with_sudo mkdir -p "$BIN_DIR"
  local target="$BIN_DIR/jojo-guest.sh"
  with_sudo cp "$0" "$target"
  with_sudo chmod 775 "$target"
}

clone_repo() {
  with_sudo mkdir -p "$REPO_DIR"
  if [ -d "${REPO_DIR}/.git" ]; then
    echo "${COLOR_PRIMARY}Atualizando repositório de referência...${STYLE_RESET}"
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
      sudo -u "$CURRENT_USER" git -C "$REPO_DIR" pull --rebase
    else
      git -C "$REPO_DIR" pull --rebase
    fi
  else
    echo "${COLOR_PRIMARY}Clonando repositório de referência...${STYLE_RESET}"
    with_sudo rm -rf "$REPO_DIR"
    with_sudo mkdir -p "$REPO_DIR"
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
      sudo -u "$CURRENT_USER" git clone "$REPO_URL" "$REPO_DIR"
    else
      git clone "$REPO_URL" "$REPO_DIR"
    fi
  fi
}

ensure_permissions() {
  with_sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$BASE_DIR"
  with_sudo chmod -R 775 "$BASE_DIR"
}

install_all() {
  install_dependencies
  install_python_dependencies
  create_directories
  materialize_assets
  deploy_self
  clone_repo
  ensure_permissions
  echo "${COLOR_SECONDARY}${STYLE_BOLD}Instalação concluída com sucesso!${STYLE_RESET}"
}

update_all() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Atualizando instalação do Jojô Guest...${STYLE_RESET}"
  create_directories
  with_sudo rm -rf "${APP_DIR}"/*
  with_sudo rm -rf "${BIN_DIR}"/*
  materialize_assets
  deploy_self
  install_python_dependencies
  clone_repo
  ensure_permissions
  echo "${COLOR_SECONDARY}${STYLE_BOLD}Atualização concluída!${STYLE_RESET}"
}

uninstall_all() {
  echo "${COLOR_WARNING}${STYLE_BOLD}Tem certeza que deseja remover o Jojô Guest? Digite SIM para confirmar:${STYLE_RESET}"
  read -r confirmation
  if [ "$confirmation" != "SIM" ]; then
    echo "${COLOR_WARNING}Ação cancelada.${STYLE_RESET}"
    return
  fi
  with_sudo rm -rf "$BASE_DIR"
  crontab -l 2>/dev/null | grep -v "# jojo-guest" | crontab - 2>/dev/null || true
  echo "${COLOR_SECONDARY}${STYLE_BOLD}Jojô Guest removido com sucesso.${STYLE_RESET}"
}

ensure_installed() {
  if [ ! -f "$PYTHON_FILE" ]; then
    echo "${COLOR_WARNING}Instalação incompleta. Executando instalação geral...${STYLE_RESET}"
    install_all
  fi
}

run_python() {
  ensure_installed
  local args=("$@")
  VERSION="$VERSION" python3 "$PYTHON_FILE" "${args[@]}"
}

configure_assessoria() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Configuração Assessoria VIP${STYLE_RESET}"
  local current_email
  current_email=$(get_env_var "ASSESSORIA_VIP_EMAIL")
  read -rp "E-mail [atual: ${current_email}]: " email
  read -rsp "Senha: " senha
  echo
  [ -n "$email" ] && set_env_var "ASSESSORIA_VIP_EMAIL" "$email"
  [ -n "$senha" ] && set_env_var "ASSESSORIA_VIP_PASSWORD" "$senha"
  echo "${COLOR_SECONDARY}Credenciais atualizadas.${STYLE_RESET}"
}

configure_google() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Configuração Google Sheets${STYLE_RESET}"
  local ids
  ids=$(get_env_var "GOOGLE_SHEETS_IDS")
  read -rp "IDs das planilhas (separados por vírgula) [${ids}]: " new_ids
  [ -n "$new_ids" ] && set_env_var "GOOGLE_SHEETS_IDS" "$new_ids"
  read -rp "Deseja importar um JSON de Service Account? (s/N): " resp
  if [[ "$resp" =~ ^[sS]$ ]]; then
    read -rp "Caminho do arquivo JSON: " json_path
    if [ -f "$json_path" ]; then
      with_sudo cp "$json_path" "$SERVICE_ACCOUNT_FILE"
      with_sudo chmod 660 "$SERVICE_ACCOUNT_FILE"
      echo "${COLOR_SECONDARY}Service Account atualizada.${STYLE_RESET}"
    else
      echo "${COLOR_ERROR}Arquivo não encontrado.${STYLE_RESET}"
    fi
  fi
}

configure_smtp() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Configuração SMTP${STYLE_RESET}"
  local host port username password from to tls ssl
  host=$(get_env_var "SMTP_HOST")
  port=$(get_env_var "SMTP_PORT")
  username=$(get_env_var "SMTP_USERNAME")
  password=$(get_env_var "SMTP_PASSWORD")
  from=$(get_env_var "SMTP_FROM")
  to=$(get_env_var "SMTP_TO")
  tls=$(get_env_var "SMTP_USE_TLS")
  ssl=$(get_env_var "SMTP_USE_SSL")
  read -rp "Host [${host}]: " new_host
  read -rp "Porta [${port}]: " new_port
  read -rp "Usuário [${username}]: " new_user
  read -rsp "Senha (deixe vazio para manter): " new_pass
  echo
  read -rp "Remetente [${from}]: " new_from
  read -rp "Destinatários padrão (vírgula) [${to}]: " new_to
  read -rp "Usar TLS? (true/false) [${tls}]: " new_tls
  read -rp "Usar SSL? (true/false) [${ssl}]: " new_ssl
  [ -n "$new_host" ] && set_env_var "SMTP_HOST" "$new_host"
  [ -n "$new_port" ] && set_env_var "SMTP_PORT" "$new_port"
  [ -n "$new_user" ] && set_env_var "SMTP_USERNAME" "$new_user"
  [ -n "$new_pass" ] && set_env_var "SMTP_PASSWORD" "$new_pass"
  [ -n "$new_from" ] && set_env_var "SMTP_FROM" "$new_from"
  [ -n "$new_to" ] && set_env_var "SMTP_TO" "$new_to"
  [ -n "$new_tls" ] && set_env_var "SMTP_USE_TLS" "$new_tls"
  [ -n "$new_ssl" ] && set_env_var "SMTP_USE_SSL" "$new_ssl"
  echo "${COLOR_SECONDARY}Configuração SMTP atualizada.${STYLE_RESET}"
}

provision_whatsapp_menu() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Provisionamento do WhatsApp Web${STYLE_RESET}"
  echo "Abrindo navegador em modo visível para provisionar sessão..."
  run_python --provision-whatsapp --headful
  set_env_var "WHATSAPP_PROVISIONED" "true"
}

connectivity_menu() {
  while true; do
    print_header
    echo "${COLOR_PRIMARY}${STYLE_BOLD}Conectividade${STYLE_RESET}"
    echo "1) Assessoria VIP (email/senha)"
    echo "2) WhatsApp Web (provisionar sessão)"
    echo "3) Google Sheets"
    echo "4) SMTP"
    echo "5) Voltar"
    read -rp "Escolha uma opção: " opt
    case "$opt" in
      1) configure_assessoria; pause_return ;;
      2) provision_whatsapp_menu; pause_return ;;
      3) configure_google; pause_return ;;
      4) configure_smtp; pause_return ;;
      5) break ;;
      *) echo "Opção inválida."; pause_return ;;
    esac
  done
}

view_last_log() {
  if compgen -G "${LOG_DIR}/jojo-guest-*.log" > /dev/null; then
    local last
    last=$(ls -1t "${LOG_DIR}"/jojo-guest-*.log | head -n1)
    echo "${COLOR_PRIMARY}${STYLE_BOLD}Último log: ${last}${STYLE_RESET}"
    echo "----------------------------------------"
    tail -n 200 "$last"
  else
    echo "Nenhum log encontrado."
  fi
}

rotate_logs_manual() {
  if compgen -G "${LOG_DIR}/jojo-guest-*.log" > /dev/null; then
    local logs
    mapfile -t logs < <(ls -1t "${LOG_DIR}"/jojo-guest-*.log)
    local index=0
    for log in "${logs[@]}"; do
      index=$((index + 1))
      if [ $index -gt $MAX_LOGS ]; then
        rm -f "$log"
      fi
    done
    echo "Rotação concluída. Mantidas ${MAX_LOGS} entradas mais recentes."
  else
    echo "Nenhum log para rotacionar."
  fi
}

create_backup() {
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local backup_file="${TMP_DIR}/backup-${timestamp}.tar.gz"
  mkdir -p "$TMP_DIR"
  mkdir -p "$CONFIG_DIR" "$LOG_DIR"
  tar -czf "$backup_file" -C "$BASE_DIR" config logs
  echo "Backup criado em: $backup_file"
}

logs_menu() {
  while true; do
    print_header
    echo "${COLOR_PRIMARY}${STYLE_BOLD}Logs & Backups${STYLE_RESET}"
    echo "1) Ver último log"
    echo "2) Rotacionar logs (manter apenas 10)"
    echo "3) Backup (config + logs)"
    echo "4) Voltar"
    read -rp "Escolha: " opt
    case "$opt" in
      1) view_last_log; pause_return ;;
      2) rotate_logs_manual; pause_return ;;
      3) create_backup; pause_return ;;
      4) break ;;
      *) echo "Opção inválida."; pause_return ;;
    esac
  done
}

cron_menu() {
  while true; do
    print_header
    echo "${COLOR_PRIMARY}${STYLE_BOLD}Agendamentos (cron)${STYLE_RESET}"
    echo "1) Criar agendamento"
    echo "2) Listar agendamentos"
    echo "3) Remover agendamento"
    echo "4) Voltar"
    read -rp "Escolha: " opt
    case "$opt" in
      1) cron_create; pause_return ;;
      2) cron_list; pause_return ;;
      3) cron_remove; pause_return ;;
      4) break ;;
      *) echo "Opção inválida."; pause_return ;;
    esac
  done
}

cron_create() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Novo agendamento${STYLE_RESET}"
  echo "1) Diário"
  echo "2) Semanal"
  echo "3) Mensal"
  read -rp "Periodicidade: " periodic
  local minute hour day month weekday expr
  case "$periodic" in
    1)
      read -rp "Hora (0-23): " hour
      read -rp "Minuto (0-59): " minute
      expr="$minute $hour * * *"
      ;;
    2)
      read -rp "Dia da semana (0-6, sendo 0=domingo): " weekday
      read -rp "Hora (0-23): " hour
      read -rp "Minuto (0-59): " minute
      expr="$minute $hour * * $weekday"
      ;;
    3)
      read -rp "Dia do mês (1-31): " day
      read -rp "Hora (0-23): " hour
      read -rp "Minuto (0-59): " minute
      expr="$minute $hour $day * *"
      ;;
    *)
      echo "Opção inválida."; return ;;
  esac
  local cron_cmd="$BIN_DIR/jojo-guest.sh --run >> $LOG_DIR/cron.log 2>&1 # jojo-guest"
  (crontab -l 2>/dev/null; echo "$expr $cron_cmd") | crontab -
  echo "Agendamento criado: $expr"
}

cron_list() {
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Agendamentos ativos:${STYLE_RESET}"
  local lines
  lines=$(crontab -l 2>/dev/null | grep "# jojo-guest")
  if [ -z "$lines" ]; then
    echo "Nenhum agendamento cadastrado."
  else
    nl -ba <<< "$lines"
  fi
}

cron_remove() {
  local entries
  mapfile -t entries < <(crontab -l 2>/dev/null)
  if [ "${#entries[@]}" -eq 0 ]; then
    echo "Nenhum cron configurado."
    return
  fi
  local filtered=()
  for line in "${entries[@]}"; do
    if [[ "$line" != *"# jojo-guest"* ]]; then
      filtered+=("$line")
    fi
  done
  printf "%s\n" "${filtered[@]}" | crontab - 2>/dev/null || crontab -r 2>/dev/null || true
  echo "Todos os agendamentos do Jojô Guest foram removidos."
}

run_installation() {
  install_all
  pause_return
}

run_execution() {
  run_python --run
  pause_return
}

run_update() {
  update_all
  run_python --run
  pause_return
}

show_about() {
  print_header
  echo "${COLOR_PRIMARY}${STYLE_BOLD}Sobre o Jojô Guest${STYLE_RESET}"
  echo "Nome: $APP_NAME"
  echo "Versão: $VERSION"
  echo "Diretório base: $BASE_DIR"
  echo "Repositório de referência: $REPO_URL"
  pause_return
}

main_menu() {
  while true; do
    print_header
    echo "${COLOR_PRIMARY}${STYLE_BOLD}Menu Principal${STYLE_RESET}"
    echo "1) Instalação Geral"
    echo "2) Conectividade"
    echo "3) Executar Agora"
    echo "4) Programação (cron)"
    echo "5) Logs & Backups"
    echo "6) Atualizar"
    echo "7) Desinstalar"
    echo "8) Sobre / Versão"
    echo "9) Sair"
    read -rp "Selecione uma opção: " option
    case "$option" in
      1) run_installation ;;
      2) connectivity_menu ;;
      3) run_execution ;;
      4) cron_menu ;;
      5) logs_menu ;;
      6) run_update ;;
      7) uninstall_all ; pause_return ;;
      8) show_about ;;
      9) exit 0 ;;
      *) echo "Opção inválida."; pause_return ;;
    esac
  done
}

handle_cli() {
  case "$1" in
    --run)
      shift
      run_python --run "$@"
      ;;
    --headful)
      shift
      run_python --run --headful "$@"
      ;;
    --dry-run)
      shift
      run_python --run --dry-run "$@"
      ;;
    --provision-whatsapp)
      shift
      run_python --provision-whatsapp --headful "$@"
      ;;
    --update)
      update_all
      ;;
    --install)
      install_all
      ;;
    --about)
      show_about
      ;;
    --help|-h)
      cat <<HELP
Uso: $0 [opções]
  --install                Executa instalação geral
  --update                 Atualiza e reinstala componentes
  --run [args]             Executa fluxo principal (aceita --headful, --dry-run, --event-id)
  --headful                Atalho para executar fluxo visível
  --dry-run                Atalho para executar fluxo em modo simulado
  --provision-whatsapp     Abre navegador para provisionar sessão do WhatsApp
  --about                  Exibe informações da versão
  --help                   Mostra esta ajuda
Sem argumentos, o menu interativo será iniciado.
HELP
      ;;
    *)
      main_menu
      ;;
  esac
}

if [ "$#" -gt 0 ]; then
  handle_cli "$@"
else
  main_menu
fi
