provider "aws" {
  region = "us-east-1"
}

// Create VPC
resource "aws_vpc" "dml-vpc" {
  cidr_block       = "10.1.0.0/16"
  tags = {
    Name = "dml-vpc"
  }
}

// Create Subnet
resource "aws_subnet" "dml-public-subnet-01" {
  vpc_id            = aws_vpc.dml-vpc.id
  cidr_block        = "10.1.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "us-east-1a"
  tags = {
    Name = "dml-public-subnet-01"
  }
}

resource "aws_subnet" "dml-private-subnet-02" {
  vpc_id            = aws_vpc.dml-vpc.id
  cidr_block        = "10.1.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "us-east-1b"
  tags = {
    Name = "dml-public-subnet-02"
  }
}

// Create Internet Gateway for VPC
resource "aws_internet_gateway" "dml-igw" {
  vpc_id = aws_vpc.dml-vpc.id
  tags = {
    Name: "dml-igw"
  }
}

// Create Route table
resource "aws_route_table" "dml-public-rt" {
  vpc_id = aws_vpc.dml-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dml-igw.id
  }
  tags = {
    Name = "dml-public-rt"
  }
}

// Associate subnet with route table
 
resource "aws_route_table_association" "dml-rta-public-subent-01" {
    subnet_id = aws_subnet.dml-public-subnet-01.id
    route_table_id = aws_route_table.dml-public-rt.id
}

resource "aws_route_table_association" "dml-rta-public-subent-02" {
    subnet_id = aws_subnet.dml-private-subnet-02.id
    route_table_id = aws_route_table.dml-public-rt.id
}

# resource "aws_instance" "WebServer" {
#     ami = "ami-023c11a32b0207432"
#     instance_type = "t2.micro"
#     key_name = "aws-key1"
#     vpc_security_group_ids = [ aws_security_group.demo-SG.id ]
#     // security_groups = [ "demo-SG" ]
#     subnet_id     = aws_subnet.dml-public-subnet-01.id
#     for_each = toset(["jenkins-master", "build-slave", "ansible"])
#     tags = {
#       Name = "${each.key}"
#     }
#   }

  resource "aws_instance" "WebServer" {
    ami = "ami-0230bd60aa48260c6"
    instance_type = "t2.micro"
    key_name = "aws-key1"
    vpc_security_group_ids = [ aws_security_group.demo-SG.id ]
    // security_groups = [ "demo-SG" ]
    subnet_id     = aws_subnet.dml-public-subnet-01.id
    for_each      = tomap({
    "jenkins-master" = <<-EOF
                #!/bin/bash
                # User data script for jenkins-master
                sudo hostnamectl set-hostname jenkins-master
                sudo yum update -y
                # Download repo
                sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
                sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
                # Download and install Jenkins
                sudo yum upgrade
                sudo dnf install java-17-amazon-corretto -y
                sudo yum install jenkins -y
                # Start Jenkins & enable service
                sudo systemctl start jenkins
                sudo systemctl enable jenkins
                sudo hostnamectl set-hostname jenkins-master
                EOF

    "maven-server" = <<-EOF
                #!/bin/bash
                # User data script for build-slave
                sudo yum update -y
                sudo useradd tomcat
                sleep 10
                sudo yum install java-1.8.0-devel -y
                sudo hostnamectl set-hostname maven-server
                sudo wget https://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo
                sudo sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
                sudo yum install apache-maven locate git -y
                sudo updatedb
                sleep 30
                sudo wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.83/bin/apache-tomcat-9.0.83.tar.gz
                sudo tar -zxvf apache-tomcat-9.0.83.tar.gz
                sudo mv apache-tomcat-9.0.83 /opt/tomcat
                sudo export JAVA_HOME=/path/to/jdk
                sudo export PATH=$JAVA_HOME/bin:$PATH
                sudo echo "export CATALINA_HOME=\"/opt/tomcat\"" >> ~/.bashrc
                sudo echo "export PATH=\"\$PATH:\$CATALINA_HOME/bin\"" >> ~/.bashrc
                source ~/.bashrc
                sleep 10 
                sudo /opt/tomcat/bin/catalina.sh start
                EOF

    "ansible-server" = <<-EOF
                #!/bin/bash
                # Install Ansible
                sudo hostnamectl set-hostname ansible-server
                sudo yum update -y
                sudo yum install -y amazon-linux-extras
                sudo yum install -y epel-release
                sudo yum install -y ansible
                # Additional configuration or tasks can be added here
                EOF
  })

  user_data = each.value

    tags = {
      Name = "${each.key}"
    }
  }

resource "aws_security_group" "demo-SG" {
  name        = "demo-SG"
  description = "Allow SSH Traffic"
  vpc_id      = aws_vpc.dml-vpc.id

  ingress {
    description      = "Allow SSH Traffic"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Jenkins Traffic"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Demo-SG"
  }
}

  module "sgs" {
    source = "../sg_eks"
    vpc_id     =     aws_vpc.dml-vpc.id
 }

  module "eks" {
       source = "../eks"
       vpc_id     =     aws_vpc.dml-vpc.id
       subnet_ids = [aws_subnet.dml-private-subnet-02.id,aws_subnet.dml-public-subnet-01.id]
       sg_ids = module.sgs.security_group_public
 }