<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">

# Open WebUI Starter

The [Open WebUI (OWUI) Starter project](https://github.com/iamobservable/open-webui-starter) is meant to provide a quick start for 
setting up Open WebUI and other applications. The starter uses templates, found at [The Starter Templates repository](https://github/com/iamobservable/starter-templates), to configuration the environment. More detail on Open WebUI configurations can be found in the [Open WebUI Docs](https://docs.openwebui.com/) and at the [formal Gitub repository](https://github.com/open-webui/open-webui).


## 👷 Project Overview

The Open WebUI Starter project started as an entry point for setting up Open WebUI. As the project has evolved, the goal is been updated to include not only Open WebUI but other server environments as well. Each server environment is defined as a template that can be built using this starter tool.

Here is a link to follow 🔗[project development](https://github.com/users/iamobservable/projects/1).

## Table of Contents
1. [Connect](#-connect-with-the-observable-world-community)
2. [Donations](#service-examples)
3. [Dependencies](#dependencies)
4. [Installation](#installation)
5. [Starter Templates](#starter-templates)
6. [Contribution](#contribution)

---

## 📢 Connect with the Observable World Community

Welcome! Join the [Observable World Discord](https://discord.gg/xD89WPmgut) to connect with like-minded 
others and get real-time support. If you encounter any challenges, I'm here to help however I can!

---

## ❤️ Subscriptions & Donations

Thank you for finding this useful! Your support means the world to me. If you’d like to [help me 
continue sharing code freely](https://github.com/sponsors/iamobservable), any subscripton or donation—no matter 
how small—would go a long way. Together, we can keep this community thriving!

---

## Dependencies

- **[Docker](https://docs.docker.com/)**: Containerization platform for running and deploying applications

---

## Installation

To install the Open WebUI Starter project, follow the steps provided.


### Install Docker

Get started by visiting the [get-started section](https://www.docker.com/get-started/) of the Docker website. The website will describe how to download and install Docker Desktop.


### Install script

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/iamobservable/open-webui-starter/main/install.sh)"
```

This command will download and install the open-webui-starter. A script will be
created in your $HOME/bin directory named "starter". It will be used to create
projects for OWUI and more. Use the syntax below to get started!

### Add $HOME/bin to your $PATH

**bash**
```bash
echo "export PATH=\"\$HOME/bin:\$PATH\"" >> $HOME/.bashrc
source $HOME/.bashrc
```

**zsh**
```zsh
echo "export PATH=\"\$HOME/bin:\$PATH\"" >> $HOME/.zshrc
source $HOME/.zshrc
```

### Usage

```bash
starter

#  -c, --create project-name   create new project
#  -r, --remove project-name   remove project
```

- This script has been tested in a linux environment
- This script has not yet been tested in a macOS environment
- A powershell script has not yet been created for Windows


#### Environment variables

A more detailed configuration can be used with the script by providing one or
more of the following environment variables.

```
EMBEDDING_MODEL
DECISION_MODEL
HOST_PORT
INSTALL_PATH
NGINX_HOST
POSTGRES_DB
POSTGRES_HOST
POSTGRES_USER
POSTGRES_PASSWORD
SECRET_KEY
TIMEZONE
```

e.g.

```bash
NGINX_HOST=192.168.1.100 starter -c project-name
```


Once the installation script is complete, [open OWUI in your browser](http://localhost:3000/).

---

## Starter Templates

*The original template configuration files have moved! They are now located in the [Open WebUI Starter Template](https://github.com/iamobservable/starter-templates/tree/main/4b35c72a-6775-41cb-a717-26276f7ae56e)*

A pre-configured server environment bundled with Docker Compose and configuration files, designed to simplify setup. They authenticate the owner, validate best practices, and enforce security, ensuring a reliable, secure, and standardized foundation for your local or cloud managed server.

As the platform evolves, more templates will be added for other tools and applications, expanding the range of use cases and ensuring a standardized, secure, and best-practice-based environment for any server setup.

[Starter Templates Repository](https://github.com/iamobservable/starter-templates)

- [Open Webui Starter Template](https://github.com/iamobservable/starter-templates/tree/main/4b35c72a-6775-41cb-a717-26276f7ae56e)


---


## 💪 Contribution

I am deeply grateful for any contributions to the Observable World project! If you’d like to contribute, 
simply fork this repository and submit a [pull request](https://github.com/iamobservable/open-webui-starter/pulls) with any improvements, additions, or fixes you’d 
like to see. I will review and consider any suggestions — thank you for being part of this journey!

---

## License

This project is licensed under the [MIT License](https://en.wikipedia.org/wiki/MIT_License). Find more in the [LICENSE document](https://raw.githubusercontent.com/iamobservable/open-webui-starter/refs/heads/main/LICENSE).

