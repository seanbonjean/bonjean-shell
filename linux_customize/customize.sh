#!/bin/bash

# define config file source URL
CLOUD_URL="https://bonjean-shell.oss-cn-hangzhou.aliyuncs.com/configs"

echo "This script customizes Bash, Vim and SSH configs for Linux..."

# check root privilege
if [ "$EUID" -ne 0 ]; then
        echo "Please run the script as root. Exiting..." >&2 # print error message to stderr
        exit 1
fi

# ask the user whether to modify SSH configuration
while true; do
        read -p "Do u want to modify SSH configuration? [Y/n]: " answer # read user input in the same line
        case "${answer,,}" in                                           # change answer into lowercase
        y)
                NEED_SSH=1
                break
                ;;
        n)
                NEED_SSH=0
                break
                ;;
        *) echo "Please enter y or n." ;;
        esac
done
# if [ -z "$1" ]; then
#         echo "Need SSH config? Take ur choice."
#         echo "Usage: $0 <true|false>"
#         exit 1
# fi
# if [ "$1" = "true" ]; then
#         NEED_SSH=1
# elif [ "$1" = "false" ]; then
#         NEED_SSH=0
# else
#         echo "INVALID INPUT"
#         exit 1
# fi

# if SSH configuration is needed, ask whether to disable password login
if [ "$NEED_SSH" -eq 1 ]; then
        # ask user to enter SSH port
        while true; do
                read -p "Please enter the SSH port number (1-65535): " SSH_PORT
                if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
                        break
                else
                        echo "Invalid port. Please enter a number between 1 and 65535."
                fi
        done
        while true; do
                read -p "Do u want to disable SSH password login? [Y/n]: " answer
                case "${answer,,}" in
                y)
                        DISABLE_SSH_PASSWORD=1
                        break
                        ;;
                n)
                        DISABLE_SSH_PASSWORD=0
                        break
                        ;;
                *) echo "Please enter y or n." ;;
                esac
        done
fi

# Confirm with the user
echo "================== Summary =================="
echo "The script will apply the following customizations:"
echo "  - Customize Bash configuration (~/.bashrc) for each user"
echo "  - Customize Vim configuration (~/.vimrc) for each user"
if [ "$NEED_SSH" -eq 1 ]; then
        echo "  - Customize SSH configuration:"
        echo "      -> Port: $SSH_PORT"
        echo "      -> Disable password login: $([ "$DISABLE_SSH_PASSWORD" -eq 1 ] && echo yes || echo no)"
fi
echo "============================================"
while true; do
        read -p "Do u want to proceed with these settings? [Y/n]: " confirm
        case "${confirm,,}" in
        y) break ;; # continue script execution
        n)
                echo "Aborted by user."
                exit 0
                ;;
        *) echo "Please enter y or n." ;;
        esac
done

WORK_DIR=$(mktemp -d /tmp/tmp.custom_config.XXXXXX)
rm_temp() {
        cd "$(dirname "$WORK_DIR")"
        rm -rf "$WORK_DIR"
        echo "Work dir cleaned."
}
trap rm_temp EXIT
echo "Work dir at: $WORK_DIR"

# check if configs folder exists in current directory
if [ -d "./configs" ]; then
        CLOUD_GET=0
        CONFIG_DIR="./configs"
        echo "Found local ./configs."
else
        CLOUD_GET=1
        CONFIG_DIR="$WORK_DIR/configs"
        mkdir -p "$CONFIG_DIR"
        echo "Local ./configs not found. Downloading from remote source ..."

        # list of required config files
        FILES=(".bashrc" ".vimrc" "mysshd_config" "disable_pwdlogin")

        for file in "${FILES[@]}"; do
                wget "$CLOUD_URL/$file" -O "$CONFIG_DIR/$file"
                if [ $? -ne 0 ]; then
                        echo "Failed to download $file from $CLOUD_URL" >&2
                        exit 1
                fi
        done

        echo "All config files downloaded to $CONFIG_DIR, and will be deleted after script execution."
fi

cp "$CONFIG_DIR/.bashrc" "$WORK_DIR/mybashrc"
cp "$CONFIG_DIR/.vimrc" "$WORK_DIR/myvimrc"
if [ "$NEED_SSH" -eq 1 ]; then
        cp "$CONFIG_DIR/mysshd_config" "$WORK_DIR/mysshd_config"
        sed -i "s/^Port\s\+\[port\]/Port $SSH_PORT/" "$WORK_DIR/mysshd_config" # replace [port] placeholder with actual port
        # append disable password login config if needed
        if [ "$DISABLE_SSH_PASSWORD" -eq 1 ]; then
                cat "$CONFIG_DIR/disable_pwdlogin" >>"$WORK_DIR/mysshd_config"
        fi
fi
cd $WORK_DIR

echo

cat mybashrc >>/root/.bashrc
cat myvimrc >>/root/.vimrc
echo "User: root config complete."
for USER_HOME in /home/*; do
        USER_NAME=$(basename $USER_HOME)
        cat mybashrc >>"$USER_HOME/.bashrc"
        cat myvimrc >>"$USER_HOME/.vimrc"
        echo "User: $USER_NAME config complete."
done
if [ "$NEED_SSH" -eq 1 ]; then
        cat mysshd_config >>/etc/ssh/sshd_config
        echo "SSH config complete."
        if [ "$DISABLE_SSH_PASSWORD" -eq 1 ]; then
                echo "Password login DISABLED,"
                echo 'pls make sure ur public key was added to "authorized_keys".'
        fi
fi

echo "All customization complete."
echo
echo "Attention:"

if [ "$NEED_SSH" -eq 1 ]; then
        if [ -x "$(command -v systemctl)" ]; then
                systemctl restart sshd
        elif [ -x "$(command -v service)" ]; then
                service sshd restart
        else
                echo "System does not support systemctl or service,"
                echo 'pls run: "reboot" to restart ur device manually.'
        fi
        echo "Change SSH port the next time u login."
        if [ "$DISABLE_SSH_PASSWORD" -eq 1 ]; then
                echo "Use ur private key the next time u login by SSH."
        fi
fi
echo 'Run "source ~/.bashrc" or launch a new SSH command line to apply changes.'
echo 'Open vim and run ":source ~/.vimrc" to apply changes.'
echo
