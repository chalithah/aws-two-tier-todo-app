# 🚀 AWS Two-Tier Todo App - Complete Deployment Guide

## Table of Contents
- [Prerequisites](#prerequisites)
- [Phase 1: Infrastructure Setup](#phase-1-infrastructure-setup)
- [Phase 2: Database Configuration](#phase-2-database-configuration)
- [Phase 3: Application Deployment](#phase-3-application-deployment)
- [Phase 4: Load Balancer Setup](#phase-4-load-balancer-setup)
- [Phase 5: Testing & Validation](#phase-5-testing--validation)
- [Troubleshooting](#troubleshooting)
- [Cost Optimization](#cost-optimization)
- [Security Checklist](#security-checklist)

---

## Prerequisites

### AWS Account Requirements
- AWS Account with billing enabled
- IAM user with administrative permissions
- AWS CLI configured (optional but recommended)
- EC2 Key Pair created in target region

### Local Environment
- SSH client (PuTTY for Windows, Terminal for Mac/Linux)
- Basic knowledge of Linux commands
- Text editor for configuration files

### Estimated Costs
```yaml
Monthly Costs (us-east-1):
  EC2 (2 × t3.micro): ~$16.70
  RDS (db.t3.micro): ~$12.60
  ALB: ~$16.20
  Data Transfer: ~$5.00
  Total: ~$50.50/month
  
Free Tier Eligible:
  - First 12 months: EC2 and RDS qualify for free tier
  - Reduced cost: ~$22/month
```

---

## Phase 1: Infrastructure Setup

### Step 1.1: Create VPC and Networking

1. **Create VPC**
   ```yaml
   VPC Settings:
     Name: TodoApp-VPC
     IPv4 CIDR: 10.0.0.0/16
     IPv6 CIDR: No IPv6 CIDR block
     Tenancy: Default
   ```

2. **Create Internet Gateway**
   ```yaml
   Internet Gateway:
     Name: TodoApp-IGW
     Attach to: TodoApp-VPC
   ```

3. **Create Subnets**
   ```yaml
   Public Subnet 1:
     Name: TodoApp-Public-1A
     VPC: TodoApp-VPC
     AZ: us-east-1a
     IPv4 CIDR: 10.0.1.0/24
     Auto-assign IPv4: Enable
   
   Public Subnet 2:
     Name: TodoApp-Public-1B
     VPC: TodoApp-VPC
     AZ: us-east-1b
     IPv4 CIDR: 10.0.2.0/24
     Auto-assign IPv4: Enable
   
   Private Subnet 1:
     Name: TodoApp-Private-1A
     VPC: TodoApp-VPC
     AZ: us-east-1a
     IPv4 CIDR: 10.0.3.0/24
     Auto-assign IPv4: Disable
   
   Private Subnet 2:
     Name: TodoApp-Private-1B
     VPC: TodoApp-VPC
     AZ: us-east-1b
     IPv4 CIDR: 10.0.4.0/24
     Auto-assign IPv4: Disable
   ```

4. **Create Route Tables**
   ```yaml
   Public Route Table:
     Name: TodoApp-Public-RT
     VPC: TodoApp-VPC
     Routes:
       - 10.0.0.0/16 → Local
       - 0.0.0.0/0 → TodoApp-IGW
     Associated Subnets:
       - TodoApp-Public-1A
       - TodoApp-Public-1B
   
   Private Route Table:
     Name: TodoApp-Private-RT
     VPC: TodoApp-VPC
     Routes:
       - 10.0.0.0/16 → Local
     Associated Subnets:
       - TodoApp-Private-1A
       - TodoApp-Private-1B
   ```

### Step 1.2: Create Security Groups

1. **ALB Security Group**
   ```bash
   # AWS CLI command (alternative to console)
   aws ec2 create-security-group \
     --group-name TodoApp-ALB-SG \
     --description "Security group for Application Load Balancer" \
     --vpc-id vpc-xxxxxxxxx
   
   # Add inbound rules
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxxxxxx \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   ```

2. **Web Server Security Group**
   ```yaml
   Console Configuration:
     Name: TodoApp-Web-SG
     Description: Security group for web servers
     VPC: TodoApp-VPC
     
     Inbound Rules:
       - Type: HTTP, Port: 80, Source: TodoApp-ALB-SG
       - Type: SSH, Port: 22, Source: Your-IP/32
       - Type: Custom TCP, Port: 3000, Source: TodoApp-ALB-SG
     
     Outbound Rules:
       - Type: All Traffic, Destination: 0.0.0.0/0
   ```

3. **Database Security Group**
   ```yaml
   Console Configuration:
     Name: TodoApp-DB-SG
     Description: Security group for RDS database
     VPC: TodoApp-VPC
     
     Inbound Rules:
       - Type: MySQL/Aurora, Port: 3306, Source: TodoApp-Web-SG
     
     Outbound Rules:
       - Type: All Traffic, Destination: 0.0.0.0/0
   ```

---

## Phase 2: Database Configuration

### Step 2.1: Create DB Subnet Group

```yaml
DB Subnet Group:
  Name: todoapp-db-subnet-group
  Description: Subnet group for TodoApp database
  VPC: TodoApp-VPC
  Subnets:
    - TodoApp-Private-1A (us-east-1a)
    - TodoApp-Private-1B (us-east-1b)
```

### Step 2.2: Create RDS Database

```yaml
Database Configuration:
  Database Creation Method: Standard create
  Engine: MySQL
  Version: 8.0.35
  Templates: Production (for Multi-AZ) or Dev/Test (for cost savings)
  
  Settings:
    DB Instance Identifier: todoapp-database
    Master Username: admin
    Master Password: [Create strong password]
    
  Instance Configuration:
    DB Instance Class: db.t3.micro
    Storage Type: General Purpose SSD (gp2)
    Allocated Storage: 20 GB
    Storage Autoscaling: Enable (max 100 GB)
    
  Availability & Durability:
    Multi-AZ Deployment: Yes (for production)
    
  Connectivity:
    VPC: TodoApp-VPC
    DB Subnet Group: todoapp-db-subnet-group
    Public Access: No
    VPC Security Groups: TodoApp-DB-SG
    
  Database Authentication:
    Password Authentication: Yes
    
  Additional Configuration:
    Initial Database Name: TodoAppDB
    Backup Retention Period: 7 days
    Backup Window: 03:00-04:00 UTC
    Maintenance Window: Sun:04:00-Sun:05:00 UTC
    Encryption: Enable
    Delete Protection: Enable
```

### Step 2.3: Create Database Schema

1. **Connect via Bastion Host (Recommended)**
   ```bash
   # Launch temporary bastion host in public subnet
   # Connect to bastion, then to RDS
   mysql -h your-rds-endpoint.region.rds.amazonaws.com -P 3306 -u admin -p
   ```

2. **Create Database and Tables**
   ```sql
   -- Connect to MySQL
   USE TodoAppDB;
   
   -- Create Tasks table
   CREATE TABLE Tasks (
       id INT AUTO_INCREMENT PRIMARY KEY,
       task_name VARCHAR(255) NOT NULL,
       task_description TEXT,
       due_date DATE NULL,
       completed BOOLEAN DEFAULT FALSE,
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
   );
   
   -- Create indexes for performance
   CREATE INDEX idx_completed ON Tasks(completed);
   CREATE INDEX idx_due_date ON Tasks(due_date);
   CREATE INDEX idx_created_at ON Tasks(created_at);
   
   -- Verify table creation
   DESCRIBE Tasks;
   SHOW INDEX FROM Tasks;
   ```

---

## Phase 3: Application Deployment

### Step 3.1: Launch EC2 Instances

1. **Instance Configuration**
   ```yaml
   Instance 1:
     Name: TodoApp-Web-1
     AMI: Amazon Linux 2023
     Instance Type: t3.micro
     Key Pair: your-key-pair
     Network: TodoApp-VPC
     Subnet: TodoApp-Public-1A
     Auto-assign Public IP: Enable
     Security Groups: TodoApp-Web-SG
     
   Instance 2:
     Name: TodoApp-Web-2
     AMI: Amazon Linux 2023
     Instance Type: t3.micro
     Key Pair: your-key-pair
     Network: TodoApp-VPC
     Subnet: TodoApp-Public-1B
     Auto-assign Public IP: Enable
     Security Groups: TodoApp-Web-SG
   ```

2. **User Data Script (Optional)**
   ```bash
   #!/bin/bash
   yum update -y
   yum install -y git
   
   # Install Node.js 18.x
   curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
   yum install -y nodejs
   
   # Install PM2 globally
   npm install -g pm2
   
   # Install and start nginx
   yum install -y nginx
   systemctl start nginx
   systemctl enable nginx
   ```

### Step 3.2: Configure First EC2 Instance

1. **Connect to Instance**
   ```bash
   ssh -i "your-key.pem" ec2-user@your-instance-public-ip
   ```

2. **Install Dependencies**
   ```bash
   # Update system
   sudo yum update -y
   
   # Install Git
   sudo yum install git -y
   
   # Install Node.js 18.x
   curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
   sudo yum install -y nodejs
   
   # Verify installations
   node --version
   npm --version
   ```

3. **Clone and Setup Application**
   ```bash
   # Clone your repository
   git clone https://github.com/yourusername/aws-two-tier-todo-app.git
   cd aws-two-tier-todo-app
   
   # Install application dependencies
   npm install
   
   # Install PM2 globally
   sudo npm install -g pm2
   ```

4. **Configure Environment Variables**
   ```bash
   # Create .env file
   nano .env
   ```
   
   ```env
   # Add the following content
   DB_HOST=your-rds-endpoint.region.rds.amazonaws.com
   DB_USER=admin
   DB_PASSWORD=your-database-password
   DB_NAME=TodoAppDB
   PORT=3306
   API_BASE_URL=http://your-alb-dns-name
   ```

5. **Start Application with PM2**
   ```bash
   # Start the application
   pm2 start index.js --name "todoapp"
   
   # Configure PM2 for auto-start
   pm2 startup
   # Follow the instructions provided by the command above
   
   # Save PM2 configuration
   pm2 save
   
   # Check status
   pm2 status
   pm2 logs
   ```

6. **Configure Nginx**
   ```bash
   # Install Nginx
   sudo yum install nginx -y
   
   # Start and enable Nginx
   sudo systemctl start nginx
   sudo systemctl enable nginx
   
   # Backup default config
   sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
   
   # Create new Nginx configuration
   sudo nano /etc/nginx/nginx.conf
   ```
   
   ```nginx
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
           }
   
           location /health {
               access_log off;
               return 200 "healthy\n";
               add_header Content-Type text/plain;
           }
       }
   }
   ```
   
   ```bash
   # Test configuration and restart
   sudo nginx -t
   sudo systemctl restart nginx
   sudo systemctl status nginx
   ```

### Step 3.3: Configure Second EC2 Instance

Repeat Step 3.2 for the second EC2 instance, ensuring both instances have the same configuration.

---

## Phase 4: Load Balancer Setup

### Step 4.1: Create Target Group

```yaml
Target Group Configuration:
  Target Type: Instances
  Target Group Name: TodoApp-TG
  Protocol: HTTP
  Port: 80
  VPC: TodoApp-VPC
  
  Health Check Settings:
    Protocol: HTTP
    Path: /
    Port: Traffic port
    Healthy Threshold: 2
    Unhealthy Threshold: 2
    Timeout: 5 seconds
    Interval: 30 seconds
    Success Codes: 200
```

### Step 4.2: Register Targets

```yaml
Register Targets:
  - Select both EC2 instances
  - Port: 80
  - Click "Include as pending below"
  - Click "Create target group"
```

### Step 4.3: Create Application Load Balancer

```yaml
Load Balancer Configuration:
  Load Balancer Type: Application Load Balancer
  Name: TodoApp-ALB
  Scheme: Internet-facing
  IP Address Type: IPv4
  
  Network Mapping:
    VPC: TodoApp-VPC
    Mappings:
      - us-east-1a: TodoApp-Public-1A
      - us-east-1b: TodoApp-Public-1B
  
  Security Groups:
    - TodoApp-ALB-SG
  
  Listeners and Routing:
    Protocol: HTTP
    Port: 80
    Default Action: Forward to TodoApp-TG
```

---

## Phase 5: Testing & Validation

### Step 5.1: Health Check Validation

1. **Check Target Group Health**
   ```bash
   # In AWS Console:
   # EC2 → Target Groups → TodoApp-TG → Targets tab
   # Verify both targets show "healthy" status
   ```

2. **Test Individual Instances**
   ```bash
   # Test instance 1
   curl http://instance-1-public-ip
   
   # Test instance 2
   curl http://instance-2-public-ip
   ```

### Step 5.2: Load Balancer Testing

1. **Access Application via ALB**
   ```bash
   # Get ALB DNS name from AWS Console
   # EC2 → Load Balancers → TodoApp-ALB