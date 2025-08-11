#!/bin/bash

# AWS Two-Tier Todo App - EC2 Instance Setup Script
# This script automates the setup of the Todo application on Amazon Linux 2023

set -e  # Exit on any error

echo "🚀 Starting AWS Two-Tier Todo App Setup..."
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root"
    exit 1
fi

# Update system packages
print_step "Updating system packages..."
sudo yum update -y
print_status "System packages updated successfully"

# Install Git
print_step "Installing Git..."
sudo yum install git -y
print_status "Git installed successfully"

# Install Node.js 18.x
print_step "Installing Node.js 18.x..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs
print_status "Node.js installed successfully"

# Verify Node.js and npm installation
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
print_status "Node.js version: $NODE_VERSION"
print_status "npm version: $NPM_VERSION"

# Install PM2 globally
print_step "Installing PM2 process manager..."
sudo npm install -g pm2
print_status "PM2 installed successfully"

# Install and configure Nginx
print_step "Installing and configuring Nginx..."
sudo yum install nginx -y

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
print_status "Nginx installed and started successfully"

# Clone the application repository
print_step "Cloning Todo application repository..."
if [ -d "aws-two-tier-todo-app" ]; then
    print_warning "Directory 'aws-two-tier-todo-app' already exists. Removing..."
    rm -rf aws-two-tier-todo-app
fi

git clone https://github.com/yourusername/aws-two-tier-todo-app.git
cd aws-two-tier-todo-app

# Install application dependencies
print_step "Installing application dependencies..."
npm install
print_status "Dependencies installed successfully"

# Create .env file from example
print_step "Setting up environment configuration..."
if [ ! -f ".env" ]; then
    cp .env.example .env
    print_warning "Please edit .env file with your database credentials:"
    print_warning "  - DB_HOST: Your RDS endpoint"
    print_warning "  - DB_PASSWORD: Your database password"
    print_warning "  - API_BASE_URL: Your ALB DNS name"
else
    print_status ".env file already exists"
fi

# Configure Nginx
print_step "Configuring Nginx reverse proxy..."
sudo tee /etc/nginx/nginx.conf > /dev/null << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://localhost:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeout settings
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Test and restart Nginx
sudo nginx -t
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    print_status "Nginx configuration updated successfully"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# Create systemd service for the application (alternative to PM2 startup)
print_step "Creating systemd service..."
sudo tee /etc/systemd/system/todoapp.service > /dev/null << EOF
[Unit]
Description=Todo App Node.js Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/aws-two-tier-todo-app
Environment=NODE_ENV=production
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
print_status "Systemd service created"

# Final instructions
echo ""
echo "🎉 Setup completed successfully!"
echo "=========================================="
print_status "Next steps:"
echo "1. Edit .env file with your database credentials:"
echo "   nano .env"
echo ""
echo "2. Start the application using one of these methods:"
echo "   Method A - Using PM2 (Recommended):"
echo "     pm2 start index.js --name todoapp"
echo "     pm2 startup"
echo "     pm2 save"
echo ""
echo "   Method B - Using systemd:"
echo "     sudo systemctl start todoapp"
echo "     sudo systemctl enable todoapp"
echo ""
echo "3. Check application status:"
echo "   pm2 status (if using PM2)"
echo "   sudo systemctl status todoapp (if using systemd)"
echo "   curl http://localhost"
echo ""
echo "4. Monitor logs:"
echo "   pm2 logs (if using PM2)"
echo "   sudo journalctl -u todoapp -f (if using systemd)"
echo "   sudo tail -f /var/log/nginx/access.log"
echo ""
print_status "Application will be available at http://your-server-ip"
print_warning "Remember to configure your Load Balancer to point to this instance!"

# Display system information
echo ""
echo "📊 System Information:"
echo "=========================================="
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"