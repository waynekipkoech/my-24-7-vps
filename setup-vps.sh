#!/bin/bash
# VPS Setup Script - runs on codespace creation
# IMPORTANT: Do NOT overwrite sshd_config - the sshd feature manages it
set -e

echo "========================================"
echo "[1/7] Installing bore..."
echo "========================================"

if ! command -v bore &> /dev/null; then
    curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-x86_64-unknown-linux-gnu.tar.gz | tar xz -C /usr/local/bin/
    echo "  bore installed: $(bore --version)"
else
    echo "  bore already installed"
fi

echo ""
echo "========================================"
echo "[2/7] Configuring SSH (non-breaking)..."
echo "========================================"

# Set root password
echo "root:Root@12345" | chpasswd
echo "  root password set"

# Enable root login + password auth WITHOUT overwriting the feature's config
# The sshd feature sets up key auth for vscode user - we only ADD root access
SSHD_CONF=/etc/ssh/sshd_config

# Ensure these settings exist (add if missing, update if present)
grep -q '^PermitRootLogin' $SSHD_CONF && sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' $SSHD_CONF || echo 'PermitRootLogin yes' >> $SSHD_CONF
grep -q '^PasswordAuthentication' $SSHD_CONF && sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD_CONF || echo 'PasswordAuthentication yes' >> $SSHD_CONF

# Restart sshd to apply
pkill -f '/usr/sbin/sshd' 2>/dev/null || true
sleep 1
/usr/sbin/sshd
echo "  sshd restarted with root+password access"

echo ""
echo "========================================"
echo "[3/7] Customizing shell prompt..."
echo "========================================"

# Root bashrc - VPS style red prompt
cat > /root/.bashrc <<'PROMPTEOF'
export PS1='\[\033[1;31m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERM=xterm-256color
alias ll='ls -la'
alias cls='clear'
export MOTD_SHOWN=pwned
unset CODESPACES
unset VSCODE_GIT_IPC_HANDLE
PROMPTEOF

echo "  root prompt: \u@\h:\w\$ "

# Also customize vscode user prompt
cat > /home/vscode/.bashrc <<'PROMPTEOF'
export PS1='\[\033[1;32m\]\u@\h\[\033[1;34m\]:\w\$ \[\033[0m\]'
export TERM=xterm-256color
alias ll='ls -la'
alias cls='clear'
export MOTD_SHOWN=pwned
PROMPTEOF

# Remove codespace branding
rm -f /etc/update-motd.d/*codespace* 2>/dev/null || true
rm -f /etc/update-motd.d/*welcome* 2>/dev/null || true
rm -f /etc/profile.d/*codespace* 2>/dev/null || true
rm -f /etc/profile.d/*welcome* 2>/dev/null || true
rm -f /etc/motd && touch /etc/motd
echo "  branding removed"

echo ""
echo "========================================"
echo "[4/7] Setting up Express server..."
echo "========================================"

cd /workspaces/my-24-7-vps

cat > server.js <<'EOF'
const express = require("express");
const app = express();
app.get("/", (req, res) => res.send("<h1>VPS Active</h1>"));
app.get("/health", (req, res) => res.json({status:"ok",uptime:process.uptime()}));
app.listen(3000, "0.0.0.0", () => console.log("Server on :3000"));
EOF

cat > package.json <<'EOF'
{"name":"my-24-7-vps","main":"server.js","scripts":{"start":"node server.js"},"dependencies":{"express":"^4.21.0"}}
EOF

npm install --silent 2>&1 | tail -3
nohup node server.js > /tmp/server.log 2>&1 &
echo "  Express on :3000"

echo ""
echo "========================================"
echo "[5/7] Deploying keepalive..."
echo "========================================"

cat > /home/vscode/keepalive.sh <<'EOF'
#!/bin/bash
mkdir -p ~/storage
while true; do
    date >> ~/storage/uptime.log
    echo "keepalive $(date +%s)" > /tmp/.keepalive_marker
    sleep 240
done
EOF
chmod +x /home/vscode/keepalive.sh
nohup bash /home/vscode/keepalive.sh > /dev/null 2>&1 &
echo "  keepalive running (4min interval)"

echo ""
echo "========================================"
echo "[6/7] Deploying bore tunnel..."
echo "========================================"

cat > /home/vscode/bore_watchdog.sh <<'EOF'
#!/bin/bash
while true; do
    pkill -f "bore local" 2>/dev/null
    sleep 2
    > /tmp/bore_output.log
    nohup bore local 22 --to bore.pub > /tmp/bore_output.log 2>&1 &
    BORE_PID=$!
    echo "[$(date)] Bore started PID=$BORE_PID" >> /tmp/bore_watchdog.log
    sleep 10
    PORT=$(grep -oP 'tcp://[\d.]+:\K\d+' /tmp/bore_output.log | tail -1)
    if [ -n "$PORT" ]; then
        echo "$PORT" > /tmp/bore_port.txt
        echo "[$(date)] Tunnel on port $PORT" >> /tmp/bore_watchdog.log
    fi
    while kill -0 $BORE_PID 2>/dev/null; do
        sleep 30
    done
    echo "[$(date)] Bore died, restarting..." >> /tmp/bore_watchdog.log
    sleep 10
done
EOF
chmod +x /home/vscode/bore_watchdog.sh
nohup bash /home/vscode/bore_watchdog.sh > /dev/null 2>&1 &
echo "  bore watchdog started"

echo ""
echo "========================================"
echo "[7/7] Waiting for tunnel + verification..."
echo "========================================"

sleep 15
BORE_PORT=$(cat /tmp/bore_port.txt 2>/dev/null)

if [ -n "$BORE_PORT" ]; then
    echo ""
    echo "  >>> BORE TUNNEL ACTIVE ON PORT: $BORE_PORT"
    echo "  >>> Host: 159.223.110.159"
    echo "  >>> User: root"
    echo "  >>> Pass: Root@12345"
else
    echo "  bore output: $(cat /tmp/bore_output.log 2>/dev/null)"
    echo "  Port not detected yet - watchdog will keep retrying"
fi

echo ""
echo "  sshd:  $(pgrep -c sshd) processes"
echo "  bore:  $(pgrep -c bore) processes"
echo "  keep:  $(pgrep -c -f keepalive.sh) processes"
echo "  web:   $(curl -s localhost:3000/health)"
echo ""
echo "SETUP COMPLETE"
