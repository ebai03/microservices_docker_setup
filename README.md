# Docker Security Setup and Hardening

This repository contains scripts and documentation for setting up a secure Docker environment on Rocky Linux 9.3, including OS hardening based on CIS benchmarks and Docker installation.

## Before You Begin

Ensure you have a Rocky Linux 9.3 VM set up according to the specifications outlined in the [VM Setup Guide](./docs/vm_setup.md). This guide provides detailed instructions on creating a VM that closely resembles the target environment in the NAC (Nube Academica Institucional).

Also, add a new user with sudo privileges to avoid running commands as root directly:

```bash
# Before any hardening or Docker installation
sudo useradd -m -G wheel newadminuser
sudo passwd newadminuser
# Test sudo access before proceeding
```

After creating the user, switch to it for the rest of the setup process:

```bash
su newadminuser
```

## Scripts Overview

Before executing any scripts, ensure they have executable permissions:

```bash
chmod +x scripts/rocky_linux_hardening.sh
chmod +x scripts/docker_install_.sh
```
The repository includes the following scripts:

- `rocky_linux_hardening.sh`: Automates the hardening of Rocky Linux 9.3 based on CIS Benchmark 2.0 recommendations.
- `docker_install_.sh`: Installs Docker with enhanced security configurations.

The order of execution is as follows:

1. Run the OS hardening script.
2. Install Docker using the provided installation script.
3. Verify the Docker installation and security settings using Docker Bench for Security.

## Docker Bench for Security

Docker Bench for Security is a script that checks for common best practices around deploying Docker containers in production. It is an open-source project maintained by Aqua Security. You can find more information about it on its [GitHub repository](https://github.com/docker/docker-bench-security?tab=readme-ov-file).

### Running Docker Bench for Security

```bash
# Direct installation
git clone https://github.com/docker/docker-bench-security.git
cd docker-bench-security

# Basic execution
sudo ./docker-bench.sh

# With report to file
sudo ./docker-bench.sh -l /tmp/docker-bench-report.txt

# Or inside a container (without direct access to the daemon)
docker run --rm --net host --pid host --userns host \
  -v /etc:/etc:ro \
  -v /lib:/lib:ro \
  -v /usr:/usr:ro \
  -v /run:/run:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  aquasec/docker-bench:latest
```
