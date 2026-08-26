#!/bin/bash
# VPS Setup Script - Runs as root inside codespace
set -e

echo "========================================"
echo "  Setting up VPS environment..."
echo "========================================"

# 1. Set root password
echo "root:Root@12345" | chpasswd
echo "[OK] Root password set"

# 2. Configure SSH for root login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
service ssh restart
echo "[OK] SSH configured for root login"

# 3. Root bashrc - real VPS feel
cat > /root/.bashrc << 'ROOTBASHRC'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TERM=xterm-256color
PS1='\[\033[1;31m\]root\[\033[0m\]@\[\033[1;32m\]\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]# '
export PS1
export HISTSIZE=10000 HISTFILESIZE=20000
shopt -s histappend
alias ll='ls -alF --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias df='df -h' alias du='du -h' alias free='free -h'
alias cls='clear'
alias update='apt update && apt upgrade -y'
alias ports='ss -tlnp'
alias processes='ps aux --sort=-%mem | head -20'
echo ''
echo '  ╔══════════════════════════════════════╗'
echo '  ║     VPS ROOT SESSION ACTIVE          ║'
echo '  ║  Uptime:' $(uptime -p) '                ║'
echo '  ╚══════════════════════════════════════╝'
echo ''
ROOTBASHRC
echo "[OK] Root bashrc configured"

# 4. Install VPS tools
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq neofetch htop vim curl wget net-tools \
  unzip tmux ncdu tree jq nmap sshpass 2>&1 | tail -1
echo "[OK] VPS tools installed"

# 5. Install bore tunnel
curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.2/bore-v0.5.2-x86_64-unknown-linux-musl.tar.gz | tar xz -C /usr/local/bin bore
echo "[OK] Bore tunnel installed"

# 6. Start Express server
cd /workspaces/my-24-7-vps
npm install --silent 2>/dev/null
nohup node server.js > /root/storage/server.log 2>&1 &
echo "[OK] Express server started on port 3000"

# 7. Keepalive - prevents codespace sleep
mkdir -p /root/storage
cat > /root/keepalive.sh << 'KA'
#!/bin/bash
while true; do
  echo "$(date -u) | VPS alive | $(uptime -p)" >> /root/storage/uptime.log
  touch /tmp/.keepalive
  curl -s http://localhost:3000/ > /dev/null 2>&1
  sleep 120
done
KA
chmod +x /root/keepalive.sh
nohup bash /root/keepalive.sh > /dev/null 2>&1 &
echo "[OK] Keepalive started"

# 8. Bore tunnel watchdog
cat > /root/bore_watchdog.sh << 'BW'
#!/bin/bash
while true; do
  bore local 22 --to bore.pub 2>&1 | tee -a /root/storage/tunnel.log
  echo "$(date -u) bore died, restarting in 5s" >> /root/storage/tunnel.log
  sleep 5
done
BW
chmod +x /root/bore_watchdog.sh
nohup bash /root/bore_watchdog.sh > /dev/null 2>&1 &
disown
echo "[OK] Bore watchdog started"

# Wait for bore port and display
sleep 8
PORT=$(grep -oP 'listening at bore\.pub:\K\d+' /root/storage/tunnel.log | tail -1)
if [ -n "$PORT" ]; then
  IP=$(dig +short bore.pub | head -1)
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║          YOUR VPS IS READY!                  ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║  Host:     $IP"
  echo "║  Port:     $PORT"
  echo "║  Username: root"
  echo "║  Password: Root@12345"
  echo "╚══════════════════════════════════════════════╝"
  echo ""
  echo "Port saved to /root/storage/bore_port.txt"
  echo "$PORT" > /root/storage/bore_port.txt
else
  echo "[WARN] Bore port not detected yet, check: cat /root/storage/tunnel.log"
fi
