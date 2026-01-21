#!/bin/bash
# setup_postgres_ha.sh
# Automação de Instalação para Cluster PostgreSQL HA (Patroni + Etcd + HAProxy + Keepalived)
# Sistema Operacional: OpenSUSE Leap 15.6
# Executar como root

set -e

echo ">>> [1/5] Configurando Kernel (sysctl)..."
cat <<EOF > /etc/sysctl.d/99-postgresql.conf
# Permitir binding de IP não local (Essencial para Keepalived VIP)
net.ipv4.ip_nonlocal_bind = 1

# Otimizações PostgreSQL
vm.swappiness = 10
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
vm.overcommit_memory = 2
vm.overcommit_ratio = 90
net.core.somaxconn = 4096
net.ipv4.tcp_keepalive_time = 7200
net.ipv4.tcp_keepalive_probes = 9
net.ipv4.tcp_keepalive_intvl = 75
EOF

sysctl -p /etc/sysctl.d/99-postgresql.conf

echo ">>> [2/5] Atualizando sistema e instalando dependências..."
# Verifica se o repositório já existe antes de adicionar
if ! zypper lr home_furlongm >/dev/null 2>&1; then
    zypper addrepo https://download.opensuse.org/repositories/home:furlongm/openSUSE_Tumbleweed/home:furlongm.repo
fi
zypper --gpg-auto-import-keys refresh

# Instalação de ferramentas de compilação e dependências Python
zypper install -y python3-pip python3-devel gcc gcc-c++ libpq5 libpqxx-devel git

echo ">>> [3/5] Instalando Componentes de Infraestrutura (Etcd, HAProxy, Keepalived)..."
zypper install -y etcd haproxy keepalived

echo ">>> [3.1/5] Configurando Watchdog (via Kernel Module 'softdog')..."
# O pacote 'watchdog' daemon é opcional se o Patroni acessar o device diretamente.
# O importante é ter o device /dev/watchdog disponível via módulo do kernel.

echo "adicionando o repositorio necessário"
zypper install -y watchdog

echo "Carregando módulo softdog..."
modprobe softdog

echo "Habilitando softdog no boot..."
echo "softdog" | sudo tee /etc/modules-load.d/softdog.conf

# Ajustar permissões para o usuário postgres acessar o watchdog
echo 'KERNEL=="watchdog*", MODE="0660", GROUP="postgres"' | sudo tee /etc/udev/rules.d/60-watchdog.rules
udevadm control --reload-rules
udevadm trigger

echo ">>> [4/5] Instalando PostgreSQL 16..."
# Verificando se o pacote postgresql16-server está disponível, caso contrário tenta padrão
if zypper search postgresql16-server | grep -q "postgresql16-server"; then
    zypper install -y postgresql16-server postgresql16-contrib postgresql16-docs
else
    echo "Pacote postgresql16-server não encontrado diretamente. Instalando postgresql-server (verifique versão instalada depois)..."
    zypper install -y postgresql-server postgresql-contrib
fi

echo ">>> [5/5] Instalando Patroni via PIP..."
# Instala Patroni com suporte a etcd
pip install patroni[etcd] psycopg2-binary

echo ">>> Preparando diretórios..."
mkdir -p /var/lib/pgsql/data
mkdir -p /etc/patroni
mkdir -p /var/lib/pgsql/wal_archive
chown -R postgres:postgres /var/lib/pgsql

echo ">>> Instalação Concluída!"
echo "PRÓXIMOS PASSOS:"
echo "1. Configure /etc/etcd/etcd.conf.yml"
echo "2. Configure /etc/patroni/patroni.yml"
echo "3. Configure /etc/haproxy/haproxy.cfg"
echo "4. Configure /etc/keepalived/keepalived.conf"
echo "5. Habilite e inicie os serviços (systemctl enable --now etcd patroni haproxy keepalived)"
