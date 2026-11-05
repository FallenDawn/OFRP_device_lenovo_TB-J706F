# Unraid self-hosted runner for TB-J706F OrangeFox

This repository's recovery build uses a self-hosted GitHub Actions runner. It does not use GitHub-hosted compute and does not require a paid GitHub runner.

## Recommended host

Use an Ubuntu 22.04 LTS VM on Unraid rather than installing Android build dependencies directly into the Unraid host.

- 8 vCPU minimum (12-16 recommended)
- 32 GB RAM minimum
- 300 GB or more free virtual disk space (45 GB is only the documented minimum for syncing fox_12.1; it is not enough for a comfortable full build and output/cache)
- Stable wired network
- Run the runner as a normal, non-root user

Do not put the source tree on an SMB/NFS share. Use the VM's local virtual disk, preferably SSD/NVMe.

## Install base tools (Ubuntu VM)

```bash
sudo apt update
sudo apt install -y git git-lfs curl wget rsync unzip zip bc bison build-essential \
  ccache flex g++-multilib gcc-multilib gnupg gperf imagemagick lib32readline-dev \
  lib32z1-dev liblz4-tool libncurses5-dev libsdl1.2-dev libssl-dev libxml2-utils \
  lzop pngcrush schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3
```

Create the persistent build directory and give it to the non-root runner account (replace `<runner-user>` with that Linux account):\n\n```bash\nsudo mkdir -p /opt/orangefox\nsudo chown -R <runner-user>:<runner-user> /opt/orangefox\n```\n\nInstall Google's `repo` launcher:

```bash
sudo curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
sudo chmod 0755 /usr/local/bin/repo
repo --version
```

OrangeFox's sync script may identify additional packages required by the selected manifest; install those if prompted. Build as the normal runner user, never as root.

## Register the runner

1. Open this repository on GitHub.
2. Go to **Settings → Actions → Runners → New self-hosted runner**.
3. Select **Linux** and **x64**.
4. Follow GitHub's current download/configuration commands on the Ubuntu VM.
5. During configuration, add the custom label exactly: `orangefox-build`.
6. Install and start the runner service using GitHub's displayed commands.

The runner must show **Idle** in repository Settings → Actions → Runners before starting a build.

Do not paste the temporary registration token into this repository, workflow, or chat. GitHub generates a short-lived token on the runner setup page.

## Start the build

After the runner is online:

1. Open **Actions → Build OrangeFox Recovery (self-hosted)**.
2. Choose **Run workflow** on branch `fix/pearl-prc-wifi-fastbootd`.
3. Leave `clean_output` disabled for the first build unless the existing output is known to be corrupt.
4. Start the workflow and inspect the complete log if it fails.

The workflow keeps the synced OrangeFox tree at `/opt/orangefox/fox_12.1`, installs this branch's device tree at `device/lenovo/pearl_prc_wifi`, applies the fastbootd slot fallback patch, and builds the separate recovery image.

Expected output from the OrangeFox build system:
`out/target/product/pearl_prc_wifi/OrangeFox-unofficial-pearl_prc_wifi.img`

The workflow checks that the image is no larger than the device's 96 MiB recovery partition and uploads the image, SHA256 file, and full build log as a GitHub Actions artifact.

## Safety

A successful compile does not prove that the image boots or that decryption, touch, USB, A/B handling, or fastbootd work on the physical tablet. Do not flash it yet. First inspect the artifact and its ramdisk, then use a temporary boot/test path if the bootloader supports it. Never erase userdata, metadata, misc, super, or vbmeta as part of this build workflow.
