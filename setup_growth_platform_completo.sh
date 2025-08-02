#!/bin/bash
# ===========================================
# SETUP AUTOMÁTICO COMPLETO - GROWTH PLATFORM TGH
# ===========================================
# Este script configura TODA a infraestrutura automaticamente
# Versão: 2.0
# Data: $(date)
# ===========================================

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações (EDITE ESTAS VARIÁVEIS!)
# ===========================================
DOMAIN="seudominio.com"  # SUBSTITUA pelo seu domínio
ADMIN_EMAIL="seu-email@dominio.com"  # SUBSTITUA pelo seu email
SUPABASE_PROJECT_ID="seu-project-id"  # SUBSTITUA pelo ID do seu projeto Supabase
SUPABASE_DB_PASSWORD="GrowthTGH2024!@#"  # SUBSTITUA pela senha do seu banco
N8N_PASSWORD="GrowthTGH2024!@#"  # SUBSTITUA pela senha do N8N

# Chaves de API (CONFIGURE ANTES DE EXECUTAR!)
SUPABASE_URL="https://${SUPABASE_PROJECT_ID}.supabase.co"
SUPABASE_ANON_KEY="sua-chave-anon-aqui"  # SUBSTITUA
SUPABASE_SERVICE_ROLE_KEY="sua-chave-service-role-aqui"  # SUBSTITUA
OPENAI_API_KEY="sk-proj-sua-chave-openai-aqui"  # SUBSTITUA
ANTHROPIC_API_KEY="sk-ant-sua-chave-anthropic-aqui"  # SUBSTITUA
GOOGLE_AI_API_KEY="AIza-sua-chave-google-aqui"  # SUBSTITUA
PERPLEXITY_API_KEY="pplx-sua-chave-perplexity-aqui"  # SUBSTITUA
SCRAPTIO_API_KEY="scrp-sua-chave-scraptio-aqui"  # SUBSTITUA

# Configurações internas
LOG_FILE="/var/log/growth-platform-setup.log"
BACKUP_DIR="/opt/backups"
INSTALL_DIR="/opt/growth-platform"

# Função de log colorido
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "${NC}[LOG]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Função para verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para verificar se serviço está rodando
service_running() {
    systemctl is-active --quiet "$1"
}

# Função para aguardar serviço ficar disponível
wait_for_service() {
    local service_name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Aguardando $service_name ficar disponível..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|401\|403"; then
            log "INFO" "$service_name está disponível!"
            return 0
        fi
        
        log "DEBUG" "Tentativa $attempt/$max_attempts - $service_name ainda não disponível"
        sleep 10
        ((attempt++))
    done
    
    log "ERROR" "$service_name não ficou disponível após $((max_attempts * 10)) segundos"
    return 1
}

# Função para fazer rollback em caso de erro
rollback() {
    log "ERROR" "Erro detectado! Iniciando rollback..."
    
    # Parar serviços
    systemctl stop nginx 2>/dev/null || true
    docker compose -f /opt/n8n/docker-compose.yml down 2>/dev/null || true
    
    # Restaurar configurações originais se existirem
    if [ -f "/etc/nginx/nginx.conf.backup" ]; then
        cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
        log "INFO" "Configuração original do Nginx restaurada"
    fi
    
    log "INFO" "Rollback concluído. Verifique os logs em $LOG_FILE"
    exit 1
}

# Configurar trap para rollback em caso de erro
trap rollback ERR

# Função principal
main() {
    log "INFO" "🚀 Iniciando setup automático da Growth Platform TGH..."
    log "INFO" "📋 Domínio: $DOMAIN"
    log "INFO" "📧 Email: $ADMIN_EMAIL"
    log "INFO" "🗄️ Supabase: $SUPABASE_PROJECT_ID"
    
    # Verificar se está rodando como root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
    
    # Verificar variáveis obrigatórias
    if [[ "$DOMAIN" == "seudominio.com" ]] || [[ "$SUPABASE_ANON_KEY" == "sua-chave-anon-aqui" ]]; then
        log "ERROR" "Configure as variáveis no início do script antes de executar!"
        log "ERROR" "Edite: DOMAIN, ADMIN_EMAIL, SUPABASE_PROJECT_ID e todas as chaves de API"
        exit 1
    fi
    
    # Criar diretórios necessários
    mkdir -p "$BACKUP_DIR" "$INSTALL_DIR" /var/log
    
    # Etapa 1: Atualizar sistema
    setup_system
    
    # Etapa 2: Instalar Docker
    install_docker
    
    # Etapa 3: Instalar e configurar Nginx
    install_nginx
    
    # Etapa 4: Configurar firewall
    setup_firewall
    
    # Etapa 5: Instalar Node.js e Supabase CLI
    install_nodejs_supabase
    
    # Etapa 6: Configurar N8N
    setup_n8n
    
    # Etapa 7: Configurar SSL
    setup_ssl
    
    # Etapa 8: Configurar monitoramento
    setup_monitoring
    
    # Etapa 9: Configurar backups
    setup_backups
    
    # Etapa 10: Validação final
    final_validation
    
    log "INFO" "✅ Setup completo! Growth Platform TGH configurada com sucesso!"
    log "INFO" "🌐 Acesse: https://$DOMAIN"
    log "INFO" "🔧 N8N: https://$DOMAIN/n8n/"
    log "INFO" "📊 Logs: $LOG_FILE"
}

# Etapa 1: Configurar sistema
setup_system() {
    log "INFO" "📦 Configurando sistema base..."
    
    # Atualizar sistema
    apt update && apt upgrade -y
    
    # Instalar dependências essenciais
    apt install -y \
        curl \
        wget \
        git \
        unzip \
        zip \
        htop \
        nano \
        vim \
        tree \
        jq \
        bc \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        build-essential \
        python3 \
        python3-pip \
        fail2ban \
        ufw \
        certbot \
        python3-certbot-nginx
    
    # Configurar timezone
    timedatectl set-timezone America/Sao_Paulo
    
    # Configurar locale
    locale-gen pt_BR.UTF-8
    update-locale LANG=pt_BR.UTF-8
    
    log "INFO" "✅ Sistema base configurado"
}

# Etapa 2: Instalar Docker
install_docker() {
    log "INFO" "🐳 Instalando Docker..."
    
    # Remover versões antigas
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Adicionar repositório Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalar Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Configurar Docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF
    
    # Iniciar Docker
    systemctl start docker
    systemctl enable docker
    
    # Adicionar usuário ao grupo docker
    usermod -aG docker root
    
    # Testar Docker
    docker run --rm hello-world > /dev/null
    
    log "INFO" "✅ Docker instalado e funcionando"
}

# Etapa 3: Instalar Nginx
install_nginx() {
    log "INFO" "🌐 Instalando e configurando Nginx..."
    
    apt install -y nginx
    
    # Backup da configuração original
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    
    # Configuração otimizada do Nginx
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # MIME
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # Remover site padrão
    rm -f /etc/nginx/sites-enabled/default
    
    # Criar configuração do site
    cat > /etc/nginx/sites-available/growth-platform << EOF
# Growth Platform TGH - Nginx Configuration
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Redirect HTTP to HTTPS (será ativado após SSL)
    # return 301 https://\$server_name\$request_uri;
    
    # Temporário: permitir acesso HTTP para configuração SSL
    location / {
        return 200 'Growth Platform TGH - Configurando SSL...';
        add_header Content-Type text/plain;
    }
    
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Ativar site
    ln -sf /etc/nginx/sites-available/growth-platform /etc/nginx/sites-enabled/
    
    # Testar e iniciar Nginx
    nginx -t
    systemctl start nginx
    systemctl enable nginx
    
    log "INFO" "✅ Nginx instalado e configurado"
}

# Etapa 4: Configurar firewall
setup_firewall() {
    log "INFO" "🔒 Configurando firewall..."
    
    # Resetar UFW
    ufw --force reset
    
    # Configurar políticas padrão
    ufw default deny incoming
    ufw default allow outgoing
    
    # Permitir SSH, HTTP e HTTPS
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Ativar firewall
    ufw --force enable
    
    # Configurar fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6
EOF
    
    systemctl start fail2ban
    systemctl enable fail2ban
    
    log "INFO" "✅ Firewall configurado"
}

# Etapa 5: Instalar Node.js e Supabase CLI
install_nodejs_supabase() {
    log "INFO" "📦 Instalando Node.js e Supabase CLI..."
    
    # Instalar Node.js LTS
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs
    
    # Instalar Supabase CLI
    curl -fsSL https://supabase.com/install.sh | sh
    
    # Adicionar ao PATH
    echo 'export PATH=$PATH:/root/.local/bin' >> ~/.bashrc
    export PATH=$PATH:/root/.local/bin
    
    # Verificar instalações
    node --version
    npm --version
    /root/.local/bin/supabase --version
    
    log "INFO" "✅ Node.js e Supabase CLI instalados"
}

# Etapa 6: Configurar N8N
setup_n8n() {
    log "INFO" "🔧 Configurando N8N..."
    
    # Criar diretórios
    mkdir -p /opt/n8n/{data,workflows,credentials,backups}
    chown -R 1000:1000 /opt/n8n
    mkdir -p /var/log/n8n
    chown -R 1000:1000 /var/log/n8n
    
    # Gerar chave de encriptação
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
    
    # Criar arquivo .env
    cat > /opt/n8n/.env << EOF
# N8N Configuration - Growth Platform TGH
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD

# Database (Supabase PostgreSQL)
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=db.$SUPABASE_PROJECT_ID.supabase.co
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=postgres
DB_POSTGRESDB_USER=postgres
DB_POSTGRESDB_PASSWORD=$SUPABASE_DB_PASSWORD
DB_POSTGRESDB_SCHEMA=n8n

# N8N Configuration
WEBHOOK_URL=https://$DOMAIN/n8n/
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY

# Timezone
GENERIC_TIMEZONE=America/Sao_Paulo
TZ=America/Sao_Paulo

# Logging
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=/var/log/n8n/n8n.log

# Security
N8N_SECURE_COOKIE=true
N8N_COOKIES_SECURE=true

# Performance
EXECUTIONS_PROCESS=main
EXECUTIONS_MODE=regular
N8N_PAYLOAD_SIZE_MAX=16

# AI APIs
OPENAI_API_KEY=$OPENAI_API_KEY
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
GOOGLE_AI_API_KEY=$GOOGLE_AI_API_KEY
PERPLEXITY_API_KEY=$PERPLEXITY_API_KEY
SCRAPTIO_API_KEY=$SCRAPTIO_API_KEY

# Supabase
SUPABASE_URL=$SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY
EOF
    
    chmod 600 /opt/n8n/.env
    
    # Criar Docker Compose
    cat > /opt/n8n/docker-compose.yml << 'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-growth-platform
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - DB_TYPE=${DB_TYPE}
      - DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}
      - DB_POSTGRESDB_SCHEMA=${DB_POSTGRESDB_SCHEMA}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${TZ}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=${N8N_LOG_OUTPUT}
      - N8N_LOG_FILE_LOCATION=${N8N_LOG_FILE_LOCATION}
      - N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
      - N8N_COOKIES_SECURE=${N8N_COOKIES_SECURE}
      - EXECUTIONS_PROCESS=${EXECUTIONS_PROCESS}
      - EXECUTIONS_MODE=${EXECUTIONS_MODE}
      - N8N_PAYLOAD_SIZE_MAX=${N8N_PAYLOAD_SIZE_MAX}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - GOOGLE_AI_API_KEY=${GOOGLE_AI_API_KEY}
      - PERPLEXITY_API_KEY=${PERPLEXITY_API_KEY}
      - SCRAPTIO_API_KEY=${SCRAPTIO_API_KEY}
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
    volumes:
      - /opt/n8n/data:/home/node/.n8n
      - /opt/n8n/workflows:/home/node/workflows
      - /opt/n8n/credentials:/home/node/credentials
      - /var/log/n8n:/var/log/n8n
    env_file:
      - .env
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  n8n-network:
    driver: bridge
    name: growth-platform-network
EOF
    
    # Iniciar N8N
    cd /opt/n8n
    docker compose up -d
    
    # Aguardar N8N inicializar
    wait_for_service "N8N" "http://localhost:5678/healthz"
    
    log "INFO" "✅ N8N configurado e rodando"
}

# Etapa 7: Configurar SSL
setup_ssl() {
    log "INFO" "🔐 Configurando SSL..."
    
    # Obter certificado SSL
    certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email $ADMIN_EMAIL
    
    # Atualizar configuração do Nginx com SSL e proxy para N8N
    cat > /etc/nginx/sites-available/growth-platform << EOF
# Growth Platform TGH - Nginx Configuration with SSL
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Logging
    access_log /var/log/nginx/growth-platform-access.log main;
    error_log /var/log/nginx/growth-platform-error.log;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=n8n:10m rate=5r/s;
    
    # N8N Proxy
    location /n8n/ {
        limit_req zone=n8n burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:5678/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_hide_header X-Powered-By;
    }
    
    # API Endpoints
    location /api/ {
        limit_req zone=api burst=50 nodelay;
        
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        
        if (\$request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type "text/plain; charset=utf-8";
            add_header Content-Length 0;
            return 204;
        }
        
        proxy_pass $SUPABASE_URL/functions/v1/;
        proxy_set_header Host db.$SUPABASE_PROJECT_ID.supabase.co;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify off;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Frontend
    location / {
        limit_req zone=api burst=100 nodelay;
        try_files \$uri \$uri/ @frontend;
    }
    
    location @frontend {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "OK\\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Testar e recarregar Nginx
    nginx -t
    systemctl reload nginx
    
    # Configurar renovação automática
    cat > /etc/cron.d/certbot-renew << 'EOF'
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF
    
    log "INFO" "✅ SSL configurado com renovação automática"
}

# Etapa 8: Configurar monitoramento
setup_monitoring() {
    log "INFO" "📊 Configurando monitoramento..."
    
    # Script de health check
    cat > /opt/health-check.sh << EOF
#!/bin/bash
LOG_FILE="/var/log/growth-platform-health.log"
ALERT_EMAIL="$ADMIN_EMAIL"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

alert() {
    local message="\$1"
    log "🚨 ALERTA: \$message"
    if command -v mail &> /dev/null && [ -n "\$ALERT_EMAIL" ]; then
        echo "\$message" | mail -s "ALERTA Growth Platform - \$(hostname)" "\$ALERT_EMAIL"
    fi
}

# Verificar Nginx
if systemctl is-active --quiet nginx; then
    log "✅ Nginx: OK"
else
    alert "Nginx não está rodando!"
    systemctl restart nginx
fi

# Verificar N8N
if docker compose -f /opt/n8n/docker-compose.yml ps | grep -q "Up"; then
    log "✅ N8N: OK"
else
    alert "N8N não está rodando!"
    cd /opt/n8n && docker compose up -d
fi

# Verificar HTTPS
if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/health | grep -q "200"; then
    log "✅ HTTPS: OK"
else
    alert "Site não acessível via HTTPS!"
fi

# Verificar espaço em disco
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 85 ]; then
    alert "Espaço em disco crítico: \${DISK_USAGE}%!"
elif [ "\$DISK_USAGE" -gt 75 ]; then
    log "⚠️ Espaço em disco: \${DISK_USAGE}%"
else
    log "✅ Espaço em disco: \${DISK_USAGE}%"
fi

# Verificar memória
MEMORY_USAGE=\$(free | awk 'NR==2{printf "%.0f", \$3*100/\$2}')
if [ "\$MEMORY_USAGE" -gt 90 ]; then
    alert "Uso de memória crítico: \${MEMORY_USAGE}%!"
else
    log "✅ Memória: \${MEMORY_USAGE}%"
fi

log "📊 Health check concluído"
EOF
    
    chmod +x /opt/health-check.sh
    
    log "INFO" "✅ Monitoramento configurado"
}

# Etapa 9: Configurar backups
setup_backups() {
    log "INFO" "💾 Configurando backups..."
    
    # Script de backup
    cat > /opt/backup.sh << EOF
#!/bin/bash
BACKUP_DIR="$BACKUP_DIR"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/backup-growth-platform.log"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

log "🔄 Iniciando backup..."

mkdir -p "\$BACKUP_DIR"

# Backup N8N
cd /opt/n8n
tar -czf "\$BACKUP_DIR/n8n-\$DATE.tar.gz" data workflows credentials .env docker-compose.yml

# Backup Nginx
tar -czf "\$BACKUP_DIR/nginx-\$DATE.tar.gz" -C /etc/nginx .

# Backup SSL
if [ -d "/etc/letsencrypt" ]; then
    tar -czf "\$BACKUP_DIR/ssl-\$DATE.tar.gz" -C /etc letsencrypt
fi

# Limpar backups antigos (mais de 7 dias)
find "\$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

log "✅ Backup concluído"
EOF
    
    chmod +x /opt/backup.sh
    
    # Configurar cron jobs
    cat > /tmp/growth-platform-cron << EOF
# Health check a cada 5 minutos
*/5 * * * * /opt/health-check.sh >/dev/null 2>&1

# Backup diário às 2h
0 2 * * * /opt/backup.sh >/dev/null 2>&1

# Limpeza de logs semanalmente
0 3 * * 0 find /var/log -name "*.log" -size +100M -exec truncate -s 50M {} \;

# Reiniciar N8N semanalmente
0 4 * * 0 cd /opt/n8n && docker compose restart >/dev/null 2>&1
EOF
    
    crontab /tmp/growth-platform-cron
    rm /tmp/growth-platform-cron
    
    log "INFO" "✅ Backups configurados"
}

# Etapa 10: Validação final
final_validation() {
    log "INFO" "🧪 Executando validação final..."
    
    # Aguardar serviços estabilizarem
    sleep 30
    
    # Testar HTTPS
    if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/health | grep -q "200"; then
        log "INFO" "✅ HTTPS funcionando"
    else
        log "ERROR" "❌ HTTPS não funcionando"
        return 1
    fi
    
    # Testar N8N
    if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/n8n/ | grep -q "200\|401"; then
        log "INFO" "✅ N8N acessível"
    else
        log "ERROR" "❌ N8N não acessível"
        return 1
    fi
    
    # Verificar containers
    if docker compose -f /opt/n8n/docker-compose.yml ps | grep -q "Up"; then
        log "INFO" "✅ Containers rodando"
    else
        log "ERROR" "❌ Containers com problema"
        return 1
    fi
    
    # Verificar serviços
    for service in nginx docker; do
        if systemctl is-active --quiet $service; then
            log "INFO" "✅ $service ativo"
        else
            log "ERROR" "❌ $service inativo"
            return 1
        fi
    done
    
    # Verificar SSL
    if openssl s_client -servername $DOMAIN -connect $DOMAIN:443 </dev/null 2>/dev/null | openssl x509 -noout -dates >/dev/null 2>&1; then
        log "INFO" "✅ Certificado SSL válido"
    else
        log "ERROR" "❌ Problema com certificado SSL"
        return 1
    fi
    
    # Executar health check
    /opt/health-check.sh
    
    log "INFO" "✅ Todas as validações passaram!"
    return 0
}

# Função para mostrar informações finais
show_final_info() {
    echo
    echo "🎉 =================================="
    echo "   GROWTH PLATFORM TGH CONFIGURADA!"
    echo "=================================="
    echo
    echo "🌐 Site Principal: https://$DOMAIN"
    echo "🔧 N8N Interface: https://$DOMAIN/n8n/"
    echo "👤 N8N Login: admin"
    echo "🔑 N8N Senha: $N8N_PASSWORD"
    echo
    echo "📊 Logs:"
    echo "   - Setup: $LOG_FILE"
    echo "   - Health: /var/log/growth-platform-health.log"
    echo "   - Backup: /var/log/backup-growth-platform.log"
    echo
    echo "💾 Backups: $BACKUP_DIR"
    echo
    echo "🔧 Comandos úteis:"
    echo "   - Health Check: /opt/health-check.sh"
    echo "   - Backup Manual: /opt/backup.sh"
    echo "   - Ver N8N Logs: docker compose -f /opt/n8n/docker-compose.yml logs -f"
    echo "   - Reiniciar N8N: cd /opt/n8n && docker compose restart"
    echo
    echo "✅ Sistema 100% funcional e monitorado!"
    echo
}

# Executar função principal
main "$@"

# Mostrar informações finais
show_final_info

log "INFO" "🎉 Setup automático concluído com sucesso!"

