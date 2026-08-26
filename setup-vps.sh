#!/bin/bash
# VPS Setup Script - runs automatically on codespace creation
set -e

echo "========================================"
echo "[1/8] Installing bore..."
echo "========================================"

# Install bore if not present
if ! command -v bore &> /dev/null; then
    curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-x86_64-unknown-linux-gnu.tar.gz | tar xz -C /usr/local/bin/
    echo "  bore installed: $(bore --version)"
else
    echo "  bore already installed"
fi

echo ""
echo "========================================"
echo "[2/8] Configuring SSH..."
echo "========================================"

# Set root password
echo "root:Root@12345" | chpasswd
echo "  root password set"

# Configure sshd for password auth
cat > /etc/ssh/sshd_config_custom <<'SSHEOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

# Merge with existing config - ensure our settings override
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat /etc/ssh/sshd_config_custom >> /etc/ssh/sshd_config
# Ensure key settings are present
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "  sshd configured"

# Restart sshd
pkill -f '/usr/sbin/sshd' 2>/dev/null || true
sleep 1
/usr/sbin/sshd
echo "  sshd restarted"

echo ""
echo "========================================"
echo "[3/8] Customizing shell prompt..."
echo "========================================"

# Root bashrc - VPS style prompt
cat > /root/.bashrc <<'EOF'
export PS1='\[\033[1;31m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERM=xterm-256color
alias ll='ls -la'
alias cls='clear'
export MOTD_SHOWN=pwned
unset CODESPACES
unset VSCODE_GIT_IPC_HANDLE
EOF

echo "  root prompt set to: \u@\h:\w\$ "

# vscode user bashrc
cat > /home/vscode/.bashrc <<'EOF'
export PS1='\[\033[1;32m\]\u@\h\[\033[1;34m\]:\w\$ \[\033[0m\]'
export TERM=xterm-256color
alias ll='ls -la'
alias cls='clear'
export MOTD_SHOWN=pwned
EOF

# Remove codespace branding
rm -f /etc/update-motd.d/*codespace* 2>/dev/null || true
rm -f /etc/update-motd.d/*welcome* 2>/dev/null || true
rm -f /etc/profile.d/*codespace* 2>/dev/null || true
rm -f /etc/profile.d/*welcome* 2>/dev/null || true
rm -f /etc/motd && touch /etc/motd
echo "  branding removed"

echo ""
echo "========================================"
echo "[4/8] Setting up Express server..."
echo "========================================"

cd /workspaces/my-24-7-vps

# Create server.js if not exists or update it
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
echo "  Express server started on :3000"

echo ""
echo "========================================"
echo "[5/8] Deploying keepalive..."
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
echo "  keepalive running (every 4min)"

echo ""
echo "========================================"
echo "[6/8] Deploying bore watchdog..."
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
    sleep 8
    PORT=$(grep -oP 'tcp://[\d.]+:\K\d+' /tmp/bore_output.log | tail -1)
    if [ -n "$PORT" ]; then
        echo "$PORT" > /tmp/bore_port.txt
        echo "[$(date)] Tunnel active on port $PORT" >> /tmp/bore_watchdog.log
    fi
    while kill -0 $BORE_PID 2>/dev/null; do
        sleep 30
    done
    echo "[$(date)] Bore died, restarting in 10s..." >> /tmp/bore_watchdog.log
    sleep 10
done
EOF
chmod +x /home/vscode/bore_watchdog.sh
nohup bash /home/vscode/bore_watchdog.sh > /dev/null 2>&1 &
echo "  bore watchdog started"

echo ""
echo "========================================"
echo "[7/8] Waiting for bore tunnel..."
echo "========================================"

sleep 12
BORE_PORT=$(cat /tmp/bore_port.txt 2>/dev/null)
BORE_LOG=$(cat /tmp/bore_output.log 2>/dev/null)

if [ -n "$BORE_PORT" ]; then
    echo "  BORE TUNNEL ACTIVE ON PORT: $BORE_PORT"
    echo "  ===================================="
    echo "  Host: 159.223.110.159"
    echo "  Port: $BORE_PORT"
    echo "  User: root"
    echo "  Pass: Root@12345"
    echo "  ===================================="
else
    echo "  WARNING: bore port not detected yet"
    echo "  bore output: $BORE_LOG"
    echo "  The watchdog will keep trying. Check: cat /tmp/bore_output.log"
fi

echo ""
echo "========================================"
echo "[8/8] Final verification..."
echo "========================================"

echo "  sshd:  $(pgrep -c sshd) processes"
echo "  bore:  $(pgrep -c bore) processes"
echo "  keepalive: $(pgrep -c -f keepalive.sh) processes"
echo "  express: $(pgrep -c -f 'node server') processes"
echo "  health: $(curl -s localhost:3000/health)"

echo ""
echo "========================================"
echo "VPS SETUP COMPLETE!"
echo "========================================"
