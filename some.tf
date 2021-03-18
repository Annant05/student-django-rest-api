provider "aws" {
  region = "us-east-1"

  access_key = "AKIA3XGRYBXM7XPZRF3P"
  secret_key = "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"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_availability_zones" "azs" {
  state = "available"
}

# data "aws_security_group" "default" {
#   vpc_id = data.aws_vpc.default.id
#   name   = "default"
# }


resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_security_group" "allow_rds" {
  name        = "allow-rds"
  description = "Allow RDS inbound traffic from ec2 sg"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "RDS from ec2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_http.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_rds"
  }
}


# resource "aws_iam_service_linked_role" "autoscaling" {
#   aws_service_name = "autoscaling.amazonaws.com"
#   description      = "A service linked role for autoscaling"

#   # Sometimes good sleep is required to have some IAM resources created before they can be used
#   provisioner "local-exec" {
#     command = "sleep 10"
#   }
# }

locals {
  user_data = <<EOF
#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Ask value for mysql root password
read -p 'db_root_password [secretpasswd]: ' db_root_password
echo

# Update system
sudo apt-get update -y

## Install APache
sudo apt-get install apache2 apache2-doc apache2-mpm-prefork apache2-utils libexpat1 ssl-cert -y

## Install PHP
apt-get install php libapache2-mod-php php-mysql -y

# Install MySQL database server
export DEBIAN_FRONTEND="noninteractive"
debconf-set-selections <<<"mysql-server mysql-server/root_password password $db_root_password"
debconf-set-selections <<<"mysql-server mysql-server/root_password_again password $db_root_password"
apt-get install mysql-server -y

# Enabling Mod Rewrite
sudo a2enmod rewrite
sudo php5enmod mcrypt

## Install PhpMyAdmin
sudo apt-get install phpmyadmin -y

## Configure PhpMyAdmin
echo 'Include /etc/phpmyadmin/apache.conf' >>/etc/apache2/apache2.conf

# Set Permissions
sudo chown -R www-data:www-data /var/www

# Restart Apache
sudo service apache2 restart
EOF
}

######
# Launch configuration and autoscaling group
######

resource "aws_db_instance" "terarajrds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.medium"
  name                 = "terarajmysql"
  username             = "mysqluser"
  password             = "123456ABCD"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.allow_rds.id]
}


resource "aws_launch_configuration" "tera_raj_lc" {
  name             = "tera-raj-lc"
  image_id         = "ami-042e8287309f5df03"
  instance_type    = "t3.micro"
  security_groups  = [aws_security_group.allow_http.id]
  user_data_base64 = base64encode(local.user_data)
  key_name = "aws-eb"
}


resource "aws_autoscaling_group" "tera_raj_asg" {
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  desired_capacity     = 1
  max_size             = 4
  min_size             = 1
  launch_configuration = aws_launch_configuration.tera_raj_lc.name
}



# module "tera-raj-module" {

#   name = "tera-raj-ac-lc-com"

#   # Launch configuration
#   #
#   # launch_configuration = "my-existing-launch-configuration" # Use the existing launch configuration
#   # create_lc = false # disables creation of launch configuration
#   lc_name = "tera-raj-lc"

#   image_id                     = "ami-0d758c1134823146a"
#   instance_type                = "t3.micro"
#   security_groups              = [aws_security_group.allow_http.id]
#   associate_public_ip_address  = true
#   recreate_asg_when_lc_changes = true

#   user_data_base64 = base64encode(local.user_data)

#   ebs_block_device = [
#     {
#       device_name           = "/dev/xvdz"
#       volume_type           = "gp2"
#       volume_size           = "50"
#       delete_on_termination = true
#     },
#   ]

#   root_block_device = [
#     {
#       volume_size           = "50"
#       volume_type           = "gp2"
#       delete_on_termination = true
#     },
#   ]

#   # Auto scaling group
#   asg_name                  = "tera-raj-asg"
#   vpc_zone_identifier       = aws_subnet_ids.all.ids
#   health_check_type         = "EC2"
#   min_size                  = 2
#   max_size                  = 4
#   desired_capacity          = 2
#   wait_for_capacity_timeout = 0
#   service_linked_role_arn   = aws_iam_service_linked_role.autoscaling.arn

#   tags = [
#     {
#       key                 = "Environment"
#       value               = "tera-raj-dev"
#       propagate_at_launch = true
#     }
#   ]

# }
