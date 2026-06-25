#!/bin/bash
# Sets up a systemd user service to automount Google Drive via Rclone
# CHECKS ~Assumes~ 'rclone config' has already been run and remote is named 'gdrive'

# 1. Check if Rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "Rclone not found. Installing..."
    sudo apt install -y rclone
else
    echo "✔ Rclone is already installed."
fi

# 2. Check if Config exists
if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
    echo "⚠ Config missing! Please run 'rclone config' manually first."
    exit 1
fi

MOUNT_POINT="$HOME/GoogleDrive"
SERVICE_FILE="$HOME/.config/systemd/user/rclone-drive.service"

# 3. Create the mount point
mkdir -p "$MOUNT_POINT"

# 4. Create the systemd service file
# Ensure directory exists
mkdir -p "$(dirname "$SERVICE_FILE")"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=RClone Mount (gdrive)
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
# Mount command breakdown:
# --vfs-cache-mode full : Essential for file compatibility (prevents corruption on some apps)
# --drive-use-trash     : Safety feature. Deleting in Linux moves files to Google Drive 'Bin' (recoverable for 30 days)
# --no-modtime          : Performance boost. Skips checking modification times on every read
# --log-file            : Logs errors to /tmp for debugging if mount fails
ExecStart=/usr/bin/rclone mount gdrive: %h/GoogleDrive \\
    --vfs-cache-mode full \\
    --drive-use-trash \\
    --no-modtime \\
    --log-file /tmp/rclone.log

# Unmount cleanly on stop
ExecStop=/bin/fusermount -u %h/GoogleDrive
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# 5. Enable and Start the service
echo "Reloading systemd daemon..."
systemctl --user daemon-reload

echo "Enabling and starting rclone-drive..."
systemctl --user enable --now rclone-drive

# 6. Verification
if systemctl --user is-active --quiet rclone-drive; then
    echo "SUCCESS: Google Drive is mounted at $MOUNT_POINT"
else
    echo "ERROR: Service failed to start. Check /tmp/rclone.log"
    systemctl --user status rclone-drive --no-pager
fi
