#!/bin/bash

# AWS Two-Tier Todo App - Deployment Script
# This script handles application deployment and updates

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="todoapp"
APP_DIR="/home/ec2-user/aws-two-tier-todo-app"
BACKUP_DIR="/home/ec2-user/backups"
LOG_FILE="/var/log/todoapp-deploy.log"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" | sudo tee -a $LOG_FILE > /dev/null
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date): [WARNING] $1" | sudo tee -a $LOG_FILE > /dev/null
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date): [ERROR] $1" | sudo tee -a $LOG_FILE > /dev/null
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
    echo "$(date): [STEP] $1" | sudo tee -a $LOG_FILE > /dev/null
}

# Function to check if service is running
check_service() {
    if pm2 describe $APP_NAME > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to create backup
create_backup() {
    print_step "Creating backup of current application..."
    
    # Create backup directory if it doesn't exist
    mkdir -p $BACKUP_DIR
    
    # Create timestamp for backup
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_NAME="todoapp_backup_$TIMESTAMP"
    
    # Copy current application to backup
    if [ -d "$APP_DIR" ]; then
        cp -r $APP_DIR "$BACKUP_DIR/$BACKUP_NAME"
        print_status "Backup created: $BACKUP_DIR/$BACKUP_NAME"
    else
        print_warning "No existing application directory found"
    fi
}

# Function to update application
update_application() {
    print_step "Updating application from Git repository..."
    
    cd $APP_DIR
    
    # Pull latest changes
    git fetch origin
    git pull origin main
    
    # Install/update dependencies
    npm install
    
    print_status "Application updated successfully"
}

# Function to run database migrations (if any)
run_migrations() {
    print_step "Checking for database migrations..."
    # Add your migration logic here if needed
    print_status "No migrations to run"
}

# Function to start application
start_application() {
    print_step "Starting application..."
    
    cd $APP_DIR
    
    if check_service; then
        print_status "Application is already running, restarting..."
        pm2 restart $APP_NAME
    else
        print_status "Starting new application instance..."
        pm2 start index.js --name $APP_NAME
    fi
    
    # Save PM2 configuration
    pm2 save
    
    print_status "Application started successfully"
}

# Function to stop application
stop_application() {
    print_step "Stopping application..."
    
    if check_service; then
        pm2 stop $APP_NAME
        print_status "Application stopped successfully"
    else
        print_warning "Application is not running"
    fi
}

# Function to check application health
health_check() {
    print_step "Performing health check..."
    
    # Wait a moment for application to start
    sleep 10
    
    # Check if application responds
    if curl -f http://localhost:3000 > /dev/null 2>&1; then
        print_status "✅ Application health check passed"
        return 0
    else
        print_error "❌ Application health check failed"
        return 1
    fi
}

# Function to check nginx status
check_nginx() {
    print_step "Checking Nginx status..."
    
    if sudo systemctl is-active --quiet nginx; then
        print_status "✅ Nginx is running"
    else
        print_warning "❌ Nginx is not running, attempting to start..."
        sudo systemctl start nginx
        if sudo systemctl is-active --quiet nginx; then
            print_status "✅ Nginx started successfully"
        else
            print_error "❌ Failed to start Nginx"
            return 1
        fi
    fi
    
    # Test Nginx configuration
    if sudo nginx -t > /dev/null 2>&1; then
        print_status "✅ Nginx configuration is valid"
    else
        print_error "❌ Nginx configuration is invalid"
        return 1
    fi
}

# Function to display application status
show_status() {
    echo ""
    echo "📊 Application Status"
    echo "=========================================="
    
    # PM2 status
    echo "PM2 Processes:"
    pm2 list
    
    echo ""
    echo "System Resources:"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
    echo "Disk Usage: $(df -h / | awk 'NR==2{printf "%s", $5}')"
    
    echo ""
    echo "Network:"
    echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
    echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
    echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
    
    echo ""
    echo "Recent Logs:"
    pm2 logs $APP_NAME --lines 5 --nostream
}

# Function to rollback to previous version
rollback() {
    print_step "Rolling back to previous version..."
    
    # Find latest backup
    LATEST_BACKUP=$(ls -t $BACKUP_DIR | head -n1)
    
    if [ -n "$LATEST_BACKUP" ]; then
        print_status "Found backup: $LATEST_BACKUP"
        
        # Stop current application
        stop_application
        
        # Move current version
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        mv $APP_DIR "${APP_DIR}_failed_$TIMESTAMP"
        
        # Restore backup
        cp -r "$BACKUP_DIR/$LATEST_BACKUP" $APP_DIR
        
        # Start application
        start_application
        
        print_status "Rollback completed successfully"
    else
        print_error "No backup found for rollback"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     - Deploy/update the application"
    echo "  start      - Start the application"
    echo "  stop       - Stop the application"
    echo "  restart    - Restart the application"
    echo "  status     - Show application status"
    echo "  health     - Perform health check"
    echo "  rollback   - Rollback to previous version"
    echo "  logs       - Show application logs"
    echo "  backup     - Create manual backup"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 status"
    echo "  $0 health"
}

# Main deployment function
deploy() {
    print_step "Starting deployment process..."
    
    # Create backup
    create_backup
    
    # Update application
    update_application
    
    # Run migrations
    run_migrations
    
    # Start/restart application
    start_application
    
    # Check Nginx
    check_nginx
    
    # Health check
    if health_check; then
        print_status "🎉 Deployment completed successfully!"
        show_status
    else
        print_error "💥 Deployment failed health check"
        echo "Would you like to rollback? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rollback
        fi
        exit 1
    fi
}

# Create log file if it doesn't exist
sudo touch $LOG_FILE
sudo chown ec2-user:ec2-user $LOG_FILE

# Main script logic
case "${1:-}" in
    deploy)
        deploy
        ;;
    start)
        start_application
        ;;
    stop)
        stop_application
        ;;
    restart)
        stop_application
        start_application
        ;;
    status)
        show_status
        ;;
    health)
        health_check
        ;;
    rollback)
        rollback
        ;;
    logs)
        pm2 logs $APP_NAME
        ;;
    backup)
        create_backup
        ;;
    *)
        show_usage
        exit 1
        ;;
esac