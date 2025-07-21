<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css">

# Open WebUI Starter

The [Open WebUI (OWUI) Starter project](https://github.com/iamobservable/open-webui-starter) 
is meant to provide a quick template for setting up Open WebUI and other server 
environments. More information can be found about configurations on the 
[Open WebUI Docs](https://docs.openwebui.com/), the [Gitub repository](https://github.com/open-webui/open-webui), 
and available [Starter Templates](https://github.com/iamobservable/starter-templates).


[![video](https://github.com/user-attachments/assets/6185c8e9-93ab-4e2a-888a-9b256783167a)](https://github.com/user-attachments/assets/b3966df3-08e2-4467-b068-c38bd94f07c4)

---

## 👷 Project Overview

The Open WebUI Starter project is an entry point into using the open-source project Open WebUI. The goal is to simplify setup and configuration. Open WebUI integrates with various Large Language Models (LLMs) and provides a private, user-friendly, and local interface for interacting with computer intelligence.

Here is a link to follow 🔗[project development](https://github.com/users/iamobservable/projects/1).

---

## Table of Contents
1. [Connect](#-connect-with-the-observable-world-community)
2. [Subscriptions & Donations](#%EF%B8%8F-subscriptions--donations)
3. [Tooling and Applications](#tooling-and-applications)
4. [Dependencies](#dependencies)
5. [Installation](#installation)
6. [Starter Templates](https://github.com/iamobservable/starter-templates)
7. [JWT Auth Validator Purpose](https://github.com/iamobservable/starter-templates/tree/main/4b35c72a-6775-41cb-a717-26276f7ae56e#jwt-auth-validator-purpose)
8. [Additional Setup](https://github.com/iamobservable/starter-templates/tree/main/4b35c72a-6775-41cb-a717-26276f7ae56e#additional-setup)
9. [Service Examples](https://github.com/iamobservable/starter-templates/tree/main/4b35c72a-6775-41cb-a717-26276f7ae56e#service-examples)
10. [Contribution](#-contribution)
11. [Star History](#-star-history)
12. [License](#license)

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

## Tooling and Applications

The starter project includes the following tooling and applications. A [Service Architecture Diagram](https://github.com/iamobservable/open-webui-starter/blob/main/docs/service-architecture-diagram.md) is also available that describes how the components are connected.

- **[JWT Auth Validator](https://github.com/iamobservable/jwt-auth-validator)**: Provides a service for the Nginx proxy to validate the OWUI token signature for restricting access
- **[Docling](https://github.com/docling-project/docling-serve)**: Simplifies document processing, parsing diverse formats — including advanced PDF understanding — and providing seamless integrations with the gen AI ecosystem (created by IBM)
- **[Edge TTS](https://github.com/rany2/edge-tts)**: Python module that using Microsoft Edge's online text-to-speech service
- **[MCP Server](https://modelcontextprotocol.io/introduction)**: Open protocol that standardizes how applications provide context to LLMs
- **[Nginx](https://nginx.org/)**: Web server, reverse proxy, load balancer, mail proxy, and HTTP cache
- **[Ollama](https://ollama.com/)**: Local service API serving open source large language models
- **[Open WebUI](https://openwebui.com/)**: Open WebUI is an extensible, feature-rich, and user-friendly self-hosted AI platform designed to operate entirely offline
- **[Postgresql](https://www.postgresql.org/)/[PgVector](https://github.com/pgvector/pgvector)**: (default PERSISTENCE ENGINE) A free and open-source relational database management system (RDBMS) emphasizing extensibility and SQL compliance (has vector addon)
- **[Redis](https://redis.io/)**: An open source-available, in-memory storage, used as a distributed, in-memory key–value database, cache and message broker, with optional durability
- **[Searxng](https://docs.searxng.org/)**: Free internet metasearch engine for open webui tool integration
- **[Sqlite](https://www.sqlite.org/index.html)**: (deprecated from project) A C-language library that implements a small, fast, self-contained, high-reliability, full-featured, SQL database engine
- **[Tika](https://tika.apache.org/)**: (default CONTENT_EXTRACTION_ENGINE) A toolkit that detects and extracts metadata and text from over a thousand different file types
- **[Watchtower](https://github.com/containrrr/watchtower)**: Automated Docker container for updating container images automatically

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

# project commands:
#       --containers    project-name                     show running containers
#   -c, --create        project-name  [--template uuid]  create new project
#   -p, --projects                                       list starter projects
#   -r, --remove        project-name                     remove project
#       --start         project-name                     start project
#       --stop          project-name                     stop project
# 
# template commands:
#       --copytemplate  template-id                      make copy of template
#       --pull                                           pull latest templates
#       --templates                                      list starter templates
# 
# system commands:
#   -u, --update                                         update starter command
```

- This script has been tested in a linux environment
- This script has not yet been tested in a macOS environment
- A powershell script has not yet been created for Windows


#### Configuration Inputs

After starting the installation, some configurations will be requested. Default values are already set, so just press enter/return if you want to accept the default values.

##### Input Types

The starter script supports several input types for dynamic configuration:

- **User Input**: Standard prompts that ask for user input with default values
- **Dynamic Inputs**:
  - `dynamic:RandStr N` - Generates a random string of length N (e.g., `dynamic:RandStr 16`)
  - `dynamic:Timezone` - Automatically detects and uses the system timezone
- **Static Inputs**:
  - `static:Str value` - Sets a static string value without user prompt (e.g., `static:Str hello world`)


---

## 💪 Contribution

I am deeply grateful for any contributions to the Observable World project! If you’d like to contribute, 
simply fork this repository and submit a [pull request](https://github.com/iamobservable/open-webui-starter/pulls) with any improvements, additions, or fixes you’d like to see. I will review and consider any suggestions — thank you for being part of this journey!


---

## ✨ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=iamobservable/open-webui-starter&type=Date)](https://www.star-history.com/#iamobservable/open-webui-starter&Date)


---

## License

This project is licensed under the [Apache 2 License](https://github.com/iamobservable/open-webui-starter?tab=Apache-2.0-1-ov-file#readme). Find more in the [LICENSE document](https://github.com/iamobservable/open-webui-starter/blob/main/LICENSE).

