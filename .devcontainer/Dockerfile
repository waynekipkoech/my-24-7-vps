FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN sudo apt-get update && sudo apt-get install -y openssh-server sudo
RUN echo 'root:wayne123' | sudo chpasswd
RUN sudo mkdir -p /var/run/sshd
RUN sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sudo bash -c 'echo "PermitRootLogin yes" >> /etc/ssh/sshd_config'
RUN sudo bash -c 'echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config'
EXPOSE 22
