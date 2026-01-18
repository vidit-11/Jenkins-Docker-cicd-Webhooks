# Jenkins-Docker-cicd-Webhooks

This repository provides a comprehensive guide to setting up a multi-stage Java CI/CD pipeline using a Jenkins Master-Slave architecture, GitHub Webhooks for automation, and Docker Hub for image hosting.
### Step 1: Infrastructure & Security Setup
Launch two **Ubuntu** instances and configure their Security Groups as follows:
 * **Instance 1 (Jenkins-Master):** Open port `8080` (Jenkins) and `22` (SSH).
 * **Instance 2 (Jenkins-Slave):** Open port `22` (SSH).

### Step 2: Install Jenkins on Master
Connect to your **Master** instance via SSH and run:
**Update and Install Java:**

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install openjdk-17-jdk -y

```

**Add Jenkins Repository:**

```bash
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

```

**Install and Start Jenkins:**

```bash
sudo apt update
sudo apt install jenkins -y
sudo systemctl start jenkins
sudo systemctl enable jenkins

```

Access the Jenkins at `http://<Master-Public-IP>:8080`. Retrieve the initial admin password with:
`sudo cat /var/lib/jenkins/secrets/initialAdminPassword`

---

### Step 3: Configure the Slave Node

Connect to your **Slave** instance via SSH to prepare the environment.

**Install Java & Docker:**

```bash
sudo apt update
sudo apt install openjdk-17-jdk docker.io -y
sudo systemctl start docker
sudo systemctl enable docker

```

**Add Jenkins User:**

```bash
sudo useradd -m -d /home/jenkins -s /bin/bash jenkins
sudo usermod -aG docker jenkins # Grant permission to use Docker

```

**Set up SSH Authentication:**

1. Switch to the jenkins user: `sudo su - jenkins`
2. Create folder: `mkdir .ssh && chmod 700 .ssh`
3. On your **Local Machine**, generate the public key from your `.pem` key:
`ssh-keygen -y -f <your-aws-key>.pem`
4. Copy that output and paste it into `/home/jenkins/.ssh/authorized_keys` on the Slave.

---

### Step 4: Link Slave to Master

Jenkins Dashboard in the browser:

1. **Add Credentials:**
* Go to **Manage Jenkins > Credentials > System > Global credentials > Add Credentials**.
* **Kind:** SSH Username with private key.
* **ID:** `slave-ssh-key` | **Username:** `jenkins`
* **Private Key:** Paste the contents of your local `.pem` file.


2. **Create the Node:**
* Go to **Manage Jenkins > Nodes > New Node**.
* **Name:** `Docker-Slave` | **Type:** Permanent Agent.
* **Remote root directory:** `/home/jenkins`
* **Labels:** `docker-agent`
* **Launch method:** Launch agents via SSH.
* **Host:** `<Slave-Private-IP>`
* **Credentials:** Select `slave-ssh-key`.
* **Host Key Verification Strategy:** "Non verifying Verification Strategy".

___

### Step 5: Configure GitHub Webhook
 * In Jenkins: Open your Pipeline job > Configure > Build Triggers > Check GitHub hook trigger for GITScm polling.
 * In GitHub: Go to Repository Settings > Webhooks > Add webhook.
   * Payload URL: `http://<YOUR_JENKINS_MASTER_IP>:8080/github-webhook/`
   * Content type: `application/json`
   * Events: Just the push event.

___

### Step 6: Multi-Stage Pipeline Configuration
Create the following files in the root of your repository:
1. **Dockerfile (Multi-Stage)**
```Docker
# Stage 1: Build
FROM maven:3.9.6-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2: Runtime
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

2. **Jenkinsfile**
```groovy
pipeline {
    agent { label 'docker-agent' } 
    environment {
        DOCKER_HUB_USER = 'yourusername'
        IMAGE_NAME      = 'java-app'
        REGISTRY        = "${DOCKER_HUB_USER}/${IMAGE_NAME}"
    }
    stages {
        stage('Checkout SCM') {
            steps { checkout scm }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    sh "docker build -t ${REGISTRY}:${BUILD_NUMBER} ."
                    sh "docker tag ${REGISTRY}:${BUILD_NUMBER} ${REGISTRY}:latest"
                }
            }
        }
        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', 
                                                passwordVariable: 'DOCKER_HUB_PASSWORD', 
                                                usernameVariable: 'DOCKER_HUB_USERNAME')]) {
                    sh "echo ${DOCKER_HUB_PASSWORD} | docker login -u ${DOCKER_HUB_USERNAME} --password-stdin"
                    sh "docker push ${REGISTRY}:${BUILD_NUMBER}"
                    sh "docker push ${REGISTRY}:latest"
                }
            }
        }
        stage('Cleanup') {
            steps {
                sh "docker rmi ${REGISTRY}:${BUILD_NUMBER} ${REGISTRY}:latest"
                sh "docker image prune -f"
            }
        }
    }
}


```
