#!/bin/bash

# Function to extract the first and second words from a string
extract_words() {
    local filename="$1"
    local first_word
    local second_word

    # Use awk to split the filename based on separators - . _
    first_word=$(echo "$filename" | awk -F '[-._]' '{print $1}')
    second_word=$(echo "$filename" | awk -F '[-._]' '{print $2}')

    # Set the extracted words
    extracted_words="$first_word-$second_word"
}

# Log function to display the current date and time with the command
log_command() {
    local command="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - Executing: $command"
    eval "$command"
}

# Prompt for cloud image link and extract filename
read -p "Enter cloud image link (default: https://cloud-images.ubuntu.com/mantic/20231014/mantic-server-cloudimg-amd64.img): " link
link=${link:-"https://cloud-images.ubuntu.com/mantic/20231014/mantic-server-cloudimg-amd64.img"}

# Extract filename from the link
filename=$(basename "$link")

# Extract the first and second words from the filename
extract_words "$filename"

# Check if the file exists; if not, download it
if [ -f "$filename" ]; then
    echo "File already exists: $filename"
else
    echo "Fetching the file from the link..."
    log_command "wget $link"
    echo "File downloaded: $filename"
fi

# Prompt for VM ID (default: random number from 700 to 800)
while true; do
    read -p "Enter VM ID (default: $(shuf -i 700-800 -n 1)): " id
    id=${id:-$(shuf -i 700-800 -n 1)}
    if [[ "$id" =~ ^[0-9]+$ ]]; then
        break
    else
        echo "Invalid input. Please enter a valid number."
    fi
done

# Prompt for VM name (default: extracted words from filename plus "-template")
read -p "Enter VM name (default: $extracted_words-template): " name
name=${name:-"$extracted_words-template"}

# Prompt for VM Bridge number (default: 0)
while true; do
    read -p "Enter VM Bridge number (default: 0): " number
    number=${number:-0}
    if [[ "$number" =~ ^[0-9]+$ ]]; then
        break
    else
        echo "Invalid input. Please enter a valid number."
    fi
done

# Prompt for VM RAM in MB (default: 1024)
while true; do
    read -p "Enter VM RAM in MB (default: 1024): " ram
    ram=${ram:-1024}
    if [[ "$ram" =~ ^[0-9]+$ ]]; then
        break
    else
        echo "Invalid input. Please enter a valid number."
    fi
done

# Rest of the script with echo statements
echo "Creating the VM..."
# Create a VM
log_command "qm create $id --name $name --memory $ram --net0 virtio,bridge=vmbr$number"

echo "Importing the disk..."
# Import the disk in qcow2 format (as unused disk)
log_command "qm importdisk $id $filename hdd -format qcow2"

echo "Attaching the disk..."
# Attach the disk to the VM using VirtIO SCSI
log_command "qm set $id --scsihw virtio-scsi-pci --scsi0 /mnt/pve/hdd/images/$id/vm-$id-disk-0.qcow2"

echo "Setting up important settings..."
# Important settings
log_command "qm set $id --ide2 hdd:cloudinit --boot c --bootdisk scsi0 --serial0 socket --vga serial0"

echo "Resizing the disk..."
# The initial disk is only 2GB, thus we make it larger
log_command "qm resize $id scsi0 +30G"

echo "Configuring network..."
# Using a DHCP server on vmbr1 or use static IP
log_command "qm set $id --ipconfig0 ip=dhcp"
#qm set "$id" --ipconfig0 ip=10.10.10.222/24,gw=10.10.10.1
log_command "qm set $id --ipconfig0 ip=dhcp"

echo "Configuring user authentication..."
# User authentication for 'ubuntu' user (optional password)
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "Generating an SSH key..."
    log_command "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
fi
echo "Adding the SSH key to the VM..."
log_command "qm set $id --sshkey ~/.ssh/id_rsa.pub"
#qm set "$id" --cipassword AweSomePassword

echo "Checking the cloud-init config..."
# Check the cloud-init config
log_command "qm cloudinit dump $id user"

echo "Creating a template and linked clone..."
# Create template and a linked clone
log_command "qm template $id"
log_command "qm clone $id $((id + 1)) --name $name-clone"
log_command "qm start $((id + 1))"

echo "Script execution completed."
