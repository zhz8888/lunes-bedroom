**English** | [中文](README.md)

# OpenList on Lunes

One-click install and startup script for running OpenList on Lunes Host nodes.

## Project Overview

This project provides all the files needed to quickly deploy OpenList on a Lunes Host node:

| File | Description |
|------|-------------|
| `install.sh` | One-click installer — auto-detects environment, downloads dependencies, installs the binary, and generates SSL certificates |
| `app.js` | Node.js process manager — starts and keeps the OpenList process alive with auto-restart on crash |
| `package.json` | Node.js project definition (v1.0.2) |

### About app.js

`app.js` is a lightweight process manager that:
- Launches the `/home/container/openlist` binary with the `server --no-prefix` arguments
- Inherits the child process stdio to the main process for proper log output
- Automatically restarts the OpenList process after a 3-second delay if it crashes unexpectedly

## Quick Start

1. Make sure to select the `node.js generic` application template when creating your node.
2. Log in to the Lunes Host control panel and navigate to your node.
3. Click the **Startup** tab, then change the `STARTUP COMMAND` value to `bash`.
4. Click the **Console** tab to return to the dashboard, then click **Start** to boot the node.
5. Once the node is running, execute the following command in the console to install OpenList:

    ```bash
    curl -s https://raw.githubusercontent.com/zhz8888/openlist-on-lunes/refs/heads/main/install.sh | env DOMAIN=node68.lunes.host VERSION='v4.2.3' LITE=false bash
    ```

    > Replace `node68.lunes.host` with the domain assigned to your node.

## Environment Variables

You can customize the installation process by setting the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `node68.lunes.host` | Domain assigned to your node, used for the SSL certificate CN |
| `VERSION` | `v4.2.3` | OpenList version to install |
| `LITE` | `false` | Install the lite version (`true`/`false`) |

### Install Script Details

`install.sh` performs 5 steps in sequence, each with timestamped, color-coded log output:

| Step | Description |
|------|-------------|
| **Step 1** | Environment Check — verify `curl`, `tar`, `openssl` are available and check disk space |
| **Step 2** | Download Application Files — fetch the latest `app.js` and `package.json` |
| **Step 3** | Download OpenList Binary — automatically selects lite or full version based on `LITE` variable |
| **Step 4** | Extract and Install — extract archive, clean up temp files, set executable permissions, verify file integrity |
| **Step 5** | Generate SSL Self-Signed Certificate — creates a 3650-day certificate using `DOMAIN` as the CN |

After installation, an **Installation Summary** is displayed, including execution statistics (success/warning/error counts), file list with sizes, and recommended next steps.

## Configuration

After installation, you need to manually edit the configuration file before starting the OpenList node.

1. Go to the control panel and click the **Files** tab.
2. Navigate to `data` -> `config.json`.
3. Edit the `scheme` section as shown below:

    ```json
    "scheme": {
        "address": "0.0.0.0",
        "http_port": 3147,
        "https_port": -1,
        "force_https": false,
        "cert_file": "/home/container/cert.pem",
        "key_file": "/home/container/key.pem",
        "unix_file": "",
        "unix_file_perm": "",
        "enable_h2c": false,
        "enable_h3": false
    },
    ```

    - `address` — set to `0.0.0.0` to allow access from all IP addresses
    - `http_port` / `https_port` — use the port assigned by the system (choose one, set the unused one to `-1`)
    - `force_https` — recommended to set to `true` when using the HTTPS port
    - For more configuration options, refer to the [OpenList Documentation](https://doc.oplist.org/configuration/configuration#scheme)

4. Click the **SAVE CONTENT** button at the bottom right to save the configuration file.
5. Click the **Startup** tab, then change the `STARTUP COMMAND` value to `node app.js`.
6. Click the **Console** tab to return to the dashboard, then click **Restart** to reboot the node.

## License

[MIT](LICENSE)
