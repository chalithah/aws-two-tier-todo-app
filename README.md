# aws-two-tier-todo-app
 production-ready, highly available two-tier web application deployed on AWS. This project utilizes Amazon EC2, Amazon RDS, and an Application Load Balancer (ALB) to create a scalable and resilient infrastructure.

# 🏗️ AWS Two-Tier Architecture - Technical Documentation

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Network Design](#network-design)
- [Security Architecture](#security-architecture)
- [Database Design](#database-design)
- [Application Architecture](#application-architecture)
- [Load Balancing Strategy](#load-balancing-strategy)
- [Monitoring & Logging](#monitoring--logging)
- [Disaster Recovery](#disaster-recovery)
- [Performance Optimization](#performance-optimization)

## Architecture Overview

### High-Level Design
```
┌─────────────────────────────────────────────────────────────┐
│                        Internet Gateway                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                Application Load Balancer                     │
│              (Multi-AZ: us-east-1a, us-east-1b)            │
└─────────────┬───────────────────────────┬───────────────────┘
              │                           │
    ┌─────────▼─────────┐       ┌─────────▼─────────┐
    │   Public Subnet   │       │   Public Subnet   │
    │   10.0.1.0/24     │       │   10.0.2.0/24     │
    │   (us-east-1a)    │       │   (us-east-1b)    │
    │                   │       │                   │
    │  ┌─────────────┐  │       │  ┌─────────────┐  │
    │  │    EC2      │  │       │  │    EC2      │  │
    │  │ Web Server  │  │       │  │ Web Server  │  │
    │  │   + Nginx   │  │       │  │   + Nginx   │  │
    │  │    + PM2    │  │       │  │    + PM2    │  │
    │  └─────────────┘  │       │  └─────────────┘  │
    └───────────────────┘       └───────────────────┘
              │                           │
              └─────────────┬─────────────┘
                            │
    ┌───────────────────────▼───────────────────────┐
    │              Private Subnets                   │
    │   10.0.3.0/24 (AZ-a) │ 10.0.4.0/24 (AZ-b)   │
    │                                               │
    │       ┌─────────────────────────────┐         │
    │       │      Amazon RDS MySQL       │         │
    │       │      (Multi-AZ Setup)       │         │
    │       │   Primary: us-east-1a       │         │
    │       │   Standby: us-east-1b       │         │
    │       └─────────────────────────────┘         │
    └───────────────────────────────────────────────┘
```

### Design Principles Applied

1. **High Availability**: Multi-AZ deployment across 2 availability zones
2. **Scalability**: Horizontal scaling ready with ALB target groups
3. **Security**: Defense in depth with multiple security layers
4. **Cost Optimization**: Right-sized instances with auto-scaling capabilities
5. **Fault Tolerance**: Automatic failover at both application and database tiers

## Network Design

### VPC Configuration
```yaml
VPC: 10.0.0.0/16
Region: us-east-1
Availability Zones: us-east-1a, us-east-1b

Subnets:
  Public Subnets:
    - Name: TodoApp-Public-1A
      CIDR: 10.0.1.0/24
      AZ: us-east-1a
      Route: Internet Gateway
    
    - Name: TodoApp-Public-1B  
      CIDR: 10.0.2.0/24
      AZ: us-east-1b
      Route: Internet Gateway

  Private Subnets:
    - Name: TodoApp-Private-1A
      CIDR: 10.0.3.0/24
      AZ: us-east-1a
      Route: NAT Gateway (for updates)
    
    - Name: TodoApp-Private-1B
      CIDR: 10.0.4.0/24  
      AZ: us-east-1b
      Route: NAT Gateway (for updates)
```

### Routing Tables
```yaml
Public Route Table:
  - 10.0.0.0/16 → Local
  - 0.0.0.0/0 → Internet Gateway

Private Route Table:
  - 10.0.0.0/16 → Local
  - 0.0.0.0/0 → NAT Gateway (optional, for package updates)
```

## Security Architecture

### Security Groups

#### ALB Security Group
```yaml
Name: TodoApp-ALB-SG
Inbound Rules:
  - Type: HTTP
    Port: 80
    Source: 0.0.0.0/0
    Description: "Allow HTTP from internet"
  
  - Type: HTTPS
    Port: 443
    Source: 0.0.0.0/0
    Description: "Allow HTTPS from internet"

Outbound Rules:
  - Type: All Traffic
    Destination: 0.0.0.0/0
```

#### Web Server Security Group
```yaml
Name: TodoApp-Web-SG
Inbound Rules:
  - Type: HTTP
    Port: 80
    Source: TodoApp-ALB-SG
    Description: "Allow HTTP from ALB only"
  
  - Type: SSH
    Port: 22
    Source: YOUR_IP/32
    Description: "SSH access for management"
  
  - Type: Custom TCP
    Port: 3000
    Source: TodoApp-ALB-SG
    Description: "Node.js app port from ALB"

Outbound Rules:
  - Type: All Traffic
    Destination: 0.0.0.0/0
```

#### Database Security Group
```yaml
Name: TodoApp-DB-SG
Inbound Rules:
  - Type: MySQL/Aurora
    Port: 3306
    Source: TodoApp-Web-SG
    Description: "MySQL access from web servers only"

Outbound Rules:
  - Type: All Traffic
    Destination: 0.0.0.0/0
```

### Security Best Practices Implemented

1. **Principle of Least Privilege**: Each security group only allows necessary traffic
2. **Defense in Depth**: Multiple security layers (ALB → EC2 → RDS)
3. **Network Segmentation**: Database isolated in private subnets
4. **Access Control**: SSH access limited to specific IP addresses
5. **Encryption**: RDS encryption at rest enabled

## Database Design

### RDS Configuration
```yaml
Engine: MySQL Community 8.0.35
Instance Class: db.t3.micro
Storage: 20GB GP2 (Auto-scaling enabled to 100GB)
Multi-AZ: Yes (High Availability)
Backup Retention: 7 days
Backup Window: 03:00-04:00 UTC
Maintenance Window: Sun 04:00-05:00 UTC
Encryption: Enabled (AWS KMS)
Deletion Protection: Enabled
```

### Database Schema
```sql
-- Database: TodoAppDB
-- Character Set: utf8mb4
-- Collation: utf8mb4_unicode_ci

CREATE TABLE Tasks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    task_name VARCHAR(255) NOT NULL,
    task_description TEXT NULL,
    due_date DATE NULL,
    completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_completed (completed),
    INDEX idx_due_date (due_date),
    INDEX idx_created_at (created_at)
);
```

### Connection Pooling Configuration
```javascript
const dbConfig = {
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    connectionLimit: 10,
    acquireTimeout: 60000,
    timeout: 60000,
    reconnect: true,
    ssl: { rejectUnauthorized: false }
};
```

## Application Architecture

### Node.js Application Structure
```
Application Components:
├── Express.js Server (Port 3000)
├── MySQL Connection Pool
├── CORS Configuration
├── Static File Serving (/public)
├── RESTful API Endpoints
└── Environment Configuration
```

### API Endpoints
```yaml
GET /tasks:
  Description: Retrieve all tasks
  Response: JSON array of tasks

POST /tasks:
  Description: Create new task
  Body: { taskName, taskDescription?, dueDate? }
  Response: { message, taskId }

PUT /tasks/:id:
  Description: Update existing task
  Body: { taskName?, taskDescription?, dueDate?, completed? }
  Response: { message }

DELETE /tasks/:id:
  Description: Delete task
  Response: { message }

GET /config:
  Description: Get API configuration
  Response: { API_BASE_URL }
```

### Process Management with PM2
```yaml
Configuration:
  Process Name: index
  Instances: 1 per EC2
  Auto Restart: Yes
  Max Memory Restart: 500MB
  Log Management: Enabled
  Startup Script: Configured for system boot
```

### Nginx Configuration
```nginx
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Health check optimization
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
```

## Load Balancing Strategy

### Application Load Balancer Configuration
```yaml
Load Balancer:
  Type: Application Load Balancer
  Scheme: Internet-facing
  IP Address Type: IPv4
  Subnets: Public subnets in both AZs

Target Group:
  Protocol: HTTP
  Port: 80
  Health Check:
    Protocol: HTTP
    Path: /
    Interval: 30 seconds
    Timeout: 5 seconds
    Healthy Threshold: 2
    Unhealthy Threshold: 2
    Success Codes: 200

Listener:
  Protocol: HTTP
  Port: 80
  Default Action: Forward to target group
```

### Traffic Distribution
- **Algorithm**: Round Robin
- **Session Affinity**: Disabled (stateless application)
- **Health Checks**: Continuous monitoring of EC2 instances
- **Automatic Failover**: Unhealthy instances removed from rotation

## Monitoring & Logging

### CloudWatch Metrics (Recommended)
```yaml
Application Load Balancer:
  - RequestCount
  - TargetResponseTime
  - HTTPCode_Target_2XX_Count
  - HTTPCode_Target_5XX_Count
  - HealthyHostCount
  - UnHealthyHostCount

EC2 Instances:
  - CPUUtilization
  - NetworkIn/NetworkOut
  - StatusCheckFailed
  - DiskReadOps/DiskWriteOps

RDS Database:
  - CPUUtilization
  - DatabaseConnections
  - ReadLatency/WriteLatency
  - FreeableMemory
  - FreeStorageSpace
```

### Log Management
```yaml
Application Logs:
  - PM2 logs: ~/.pm2/logs/
  - Nginx access logs: /var/log/nginx/access.log
  - Nginx error logs: /var/log/nginx/error.log
  - System logs: /var/log/messages

Recommended CloudWatch Log Groups:
  - /aws/ec2/todoapp/application
  - /aws/ec2/todoapp/nginx
  - /aws/rds/todoapp/error
```

## Disaster Recovery

### RDS Multi-AZ Failover
```yaml
Primary Database: us-east-1a
Standby Database: us-east-1b
Failover Time: < 2 minutes
Automatic: Yes
Data Loss: Zero (synchronous replication)
```

### Application Tier Recovery
```yaml
EC2 Instance Failure:
  Detection: ALB health checks (30-second interval)
  Response: Traffic redirected to healthy instance
  Recovery Time: < 1 minute
  
Total Application Failure:
  Manual Recovery: Launch new EC2 instances
  Estimated RTO: < 15 minutes
  Estimated RPO: Zero (database intact)
```

### Backup Strategy
```yaml
RDS Automated Backups:
  Retention Period: 7 days
  Backup Window: 03:00-04:00 UTC
  Point-in-Time Recovery: Yes
  
Application Code:
  Source Control: Git repository
  Deployment: Manual (can be automated)
  
Configuration:
  Environment Variables: Documented
  Infrastructure: Repeatable deployment guide
```

## Performance Optimization

### Database Optimization
```sql
-- Indexes for common queries
CREATE INDEX idx_tasks_completed ON Tasks(completed);
CREATE INDEX idx_tasks_due_date ON Tasks(due_date);
CREATE INDEX idx_tasks_created_at ON Tasks(created_at);

-- Connection pool settings
SET GLOBAL max_connections = 151;
SET GLOBAL innodb_buffer_pool_size = 134217728; -- 128MB for t3.micro
```

### Application Optimization
```javascript
// Connection pooling for better performance
const pool = mysql.createPool({
    connectionLimit: 10,
    acquireTimeout: 60000,
    timeout: 60000,
    reconnect: true
});

// Prepared statements for SQL injection prevention
const [result] = await db.execute(
    'INSERT INTO Tasks (task_name, task_description, due_date) VALUES (?, ?, ?)',
    [taskName, taskDescription, dueDate]
);
```

### Caching Strategy (Future Enhancement)
```yaml
Recommended Implementation:
  - ElastiCache Redis for session storage
  - Application-level caching for frequent queries
  - CDN (CloudFront) for static assets
  - Browser caching headers for CSS/JS
```

---

## Conclusion

This architecture demonstrates enterprise-level cloud design principles with a focus on:

- **Reliability**: 99.9%+ uptime through Multi-AZ deployment
- **Security**: Defense-in-depth security model
- **Scalability**: Ready for horizontal scaling
- **Cost-Effectiveness**: Free tier eligible with optimization
- **Maintainability**: Clear separation of concerns and documentation

The design follows AWS Well-Architected Framework principles and is production-ready for small to medium workloads with room for future enhancements.
