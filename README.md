# arch-install
Encrypted Arch Linux install script

## Disclaimer
I only built this to catter to my own personal needs. It has not been tested for use cases other than mine and might be buggy or not match your expectations.

## Description
This simple script prompts you for:
* Username
* Hostname
* Disk encryption password
* User account password
* Installation device

It then creates an encrypted arch install using the information you just provided.

## Usage
1. Boot a Live Arch install environnement
2. Make sure you are connected to the internet
3. `curl -s https://github.com/alva-v/arch-install/blob/main/install.sh | bash`
4. Enter the requested info
5. Wait and reboot when asked to
6. Voila!
