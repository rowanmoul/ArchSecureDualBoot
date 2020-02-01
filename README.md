# Dual Booting Arch Linux and Windows 10 with Secure Boot and Encrypted Disks
So you want to dual boot Arch Linux and Windows 10, both with disk encryption. On Windows you have bitlocker turned on which encrpyts your disk without requiring a password on every boot. Then you disable secure boot to install Arch and now bitlocker is demanding that you either turn secure boot back on, or enter your recovery key each and every time you boot windows. Not ideal. This guide will help you take control of secure boot on your computer so that you can sign your Linux kernel and run it with secure boot turned on, as well as show you how to set up "bitlocker-like" disk encryption for your Linux partition (so you don't have to enter a password every time for linux either). It is not for beginners, and expects a certain knowledge level of Linux, or at least an ability to look things up and learn as you go, just as with many other aspects of running Arch Linux as opposed to Ubuntu or similar "user friendly" distributions. While this guide attempts to include as many details as possible, it is far from exhaustive, and it is up to the reader to fill in the gaps.

## Before You Begin
You want to disable Windows Bitlocker before proceeding, as we will be making changes that will result in the TPM not releasing the keys needed to decrypt the disk automatically. Read on to understand what this means (indeed, it is strongly suggested that you read the entire guide and suggested reference material before you begin so you can do further research to answer any questions you might have).  
For disk encryption on Linux, it is easier to setup before installing Linux, as it involves the creation of a new encrypted logical volume on top of a physical partition. Alternatively, you can take a backup, or use remaining free space on the disk temporarily. This guide will only cover encrypting a new Linux installation (indeed, it briefly runs through installing a barebones Arch Linux system).  
Also, be sure to install the `rng-tools` package (this is not included on an Arch live disk by default) and start `rngd.service`. This will feed output from any hardware random number generators on your system (such as a TPM) into `/dev/random` and `/dev/urandom`, which are used to help with cryptogrphic key generation. Getting into why this matters is well beyond the scope of this guide, but suffice it to say, this will help ensure your system has enough entropy to generate strong cryptographic keys that cannot be reproduced easily.  
The actual procedure described here should take about an hour if you already know what you are doing (because you read the guide through first).

## How Bitlocker securely encrypts your drive without requiring a password at every boot.
Bitlocker works by storing your disk's encryption key in a hardware device called a Trusted Platform Module, or TPM. 

### What is a TPM?
For a good overview of what a TPM is and what it can do, go read [this](https://en.wikipedia.org/wiki/Trusted_Platform_Module) and the first chapter of [this book](https://link.springer.com/book/10.1007%2F978-1-4302-6584-9) (or all of it really). That free book is arguably the single most useful resource for understanding the otherwise poorly docmented TPM.  
The TPM can do a lot of things, but in the case of bitlocker (as well as what we are about to do in linux) it is used to cryptographically secure our disk encryption key in such a way that it can only be retrieved if the machine boots with the software we expect ([Platform Integrity](https://en.wikipedia.org/wiki/Trusted_Platform_Module#Platform_integrity)). This means that if someone where to try to boot from a live disk, or replace your bootloader or kernel ([evil maid attack](https://en.wikipedia.org/wiki/Evil_maid_attack)), the TPM will not release the disk encryption key.  
But wait, I read that Wikipedia page! It said there were ways extract secrets from TPMs! Yes, it's not a flawless system, but if you read further about it, the only people with the resources to carry out such attacks probably already have your data, if they even want it. Joe Smith who picks up your lost laptop bag on the train and takes it home won't be able to. Consider what your realistic [threat model](https://en.wikipedia.org/wiki/Threat_model) is, and if this is something you need to be concerned with, this guide isn't what you need. Instead, you may want to get yourself a giant magnet to repel any [$5 wrenches](https://xkcd.com/538/) that might be swung in your direction.

### TPM Deep Dive
This section, despite it's name, will really only scratch the surface, but it should give enough of an overview of how the TPM works that you will understand it's usage in this guide. Again, the free ebook linked above and at the end of this guide contains a wealth of information if you want to do a true deep dive like did in order to write this guide. You won't find a better resource.

#### Platform Configuration Registers
Platform Configuration Registers, or PCRs are the key feature of the TPM that we will be using. They are volatile memory locations within the TPM where the computer's firmware records "measurements" of the software that executes during the boot process (and possibly after boot as well). The values of the PCRs can be used to "seal" an encryption key (or another TPM object) with a policy that only allows the key to be released if the PCRs have the same value as they did when the polcy was created (which it is up to the user to determine is a trusted configuration). This is secure because unlike CPU registers, PCRs cannot be overritten or reset. They can only be "extended". All PCRs are initialized to zero at first power. Measurements are "extended" into the PCR by the firmware by passing the measurement to the TPM, which then "ORs" that data with the existing data in the PCR, takes a cryptograhic hash of the new value (usually sha1 or sha256) and then writes the hash digest to the PCR. "Measurements" are typically another cryptographic hash of the software binary or other data (such as configuration data) that is being measured.  
A minimum of 24 PCRs are required on a standard PC. 
Different PCRs contain measurements of different parts of the boot process. The TCG (the creators of the TPM specification) define which values should be extended into each PCR. It took me far too long to find this information as it wasn't in the main spec, but it can be found in the [PC Client Platform Firmware Profile
Specification](https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification/). To save you from reading that document, I have boiled the relevant parts down into the table below:  
PCR&nbsp;&nbsp;&nbsp;|Description
---------------------|-----------
0                    |UEFI BIOS Binary from ROM
1                    |BIOS Configuration Settings from NVRAM
2                    |??
3                    |??
4                    |Boot Loader (eg. GRUB)
5                    |Boot Loader config (EFI boot entry path), and Drive Partition Table
6                    |Platform Specific (your computer manufacturer can use this for whatever they want)
7                    |Secure Boot Policy
8-15                 |Designated for use by the Operating System. For the purposes of this guide, note that GRUB extends measurements of it's configuration as well as your kernel image and initramfs into PCR 8
16                   |Debug PCR. Note that this PCR can be reset manually without rebooting.
17-22                |Reserved for Future use.
23                   |??

## Installing Arch Linux on an Encrypted Disk alongside Windows with Bitlocker
This guide wasn't initially going to include Arch Installation steps, but it is easiest to set all this up while doing a fresh install. Only steps that are not part of a typical install will be covered in detail. Everything else will be listed in brief only. See the [Official Install Guide](https://wiki.archlinux.org/index.php/Installation_guide) for details. Further, these steps will only install the bare minimum needed to boot Arch and do everything outlined in this guide.

### Pre Installation
See [Pre Installation](https://wiki.archlinux.org/index.php/Installation_guide#Pre-installation).
Stop at *Partition the Disks* and come back.  
For the purposes of this guide, I will assume you have already paritioned the drive under Windows.  
Assumptions:
- Windows and Linux will reside on separate partitions on the same disk, with a shared EFI system partition. 
- You have already installed Windows, and then used Windows disk manager to shrink `C` and create a new unformatted partition for Linux.

Doing it this way is suggested as Windows is a lot pickier about drive layout and partition locations.
An example partition scheme after doing this might be the following:
- /dev/sda1 - MS Recovery
- /dev/sda2 - EFI
- /dev/sda3 - MS Reserved
- /dev/sda4 - Windows C
- /dev/sda5 - LUKS Partition *- to be formatted below*

We will be using this example partition map in the below commands. **Make sure you modify them to suit your system.**

### Setting up the Disk Encryption
The next step is to set up disk encryption for your Linux partition. This will not be true full disk encryption because we will only be encrypting the Linux partition, but since our windows partition is encrypted with BitLocker, nearly the whole drive ends up being encrypted, just with different keys. We will not be encrypting the efi system partition, instead relying on secure boot signing to prevent tampering. If you want an encrypted efi partition that is beyond the scope of this guide, but there are guides avaiable online that can help with this.  
For the purposes of this guide, we will only be encrpyting a single partition, with the assumption that your entire Linux system is on that partion, rather than having separate partitions for directories like `/home` which aren't necessary in most single-user cases.

#### dm-crypt and LUKS
`dm-crypt` is a Linux kernel module that is part of the kernel device mapper framework. If you are framiliar with LVM or software RAID, it uses the same base kernel functionality with the addition of encryption. `dm-crypt` supports multiple disk encrpytion methods and can even be stacked with LVM and/or RAID.  
Here we will be using LUKS encryption on a single volume mapped to a single real disk partition. LUKS stands for Linux Unified Key Setup and is the de facto standard for disk encryption on Linux, providing a consistent transferable system across distributions. For more information on LUKS and how it works, look at #4 in the resources section on drive encryption.

#### Creating a LUKS encrypted Volume with `cryptsetup`
To help set everything up, we will use `cryptsetup`, which is the most commonly used cli for `dm-crypt` based disk encryption, as well as the reference implementation for LUKS. The version used to make this guide was 2.2.2  

##### Format the partition

Assuming that your drive is already partitioned the way you want, the following command will format the given partition as a LUKS partition:
```
# cryptsetup -y -v luksFormat /dev/sda5
```
`-y` requires the passcode to unlock the LUKS partition to be entered twice, similar to other "comfirm your password" mechanisms.  
`-v` enables verbose mode.  
`luksFormat` tells `cryptsetup` to format the given device as a LUKS device.  
`/dev/sda5` the device to format as a LUKS device.  
There are a multitude of other options available surrounding how keys are generated, among other things, but in general the defaults will be more than enough for you unless you are using an older/less powerful computer or have specific requirements. Do your own reading to determine which other settings you might want. The `cryptsetup` FAQ and manpage (resource #2 and #3 contain a wealth of information.)  

##### Open the LUKS partition

After formatting the partition, we want to open it so that we can create the filesystem and mount it for writing. To open our encrpyted LUKS partition, we use the following command:
```
# cryptsetup open /dev/sda5 cryptroot
```
`open` tells `cryptsetup` we want to open a LUKS device.  
`/dev/sda5` is the LUKS device we want to open.  
`cryptroot` is the name we want to map the LUKS device to. This can be any name you want. It will be made available at `/dev/mapper/cryptroot` (or whatever name you gave it).  
Running the command as above will prompt you for your passphrase, after which the LUKS device will be mapped as specified.

##### Create the filesystem and mount it
This part happens exactly like it would for a regular partition, except you are pointing at a different device in `/dev`
```
# mkfs.ext4 /dev/mapper/cryptroot
# mount /dev/mapper/cryptroot /mnt
```
At this point you may want to quickly verify that everything is working by unmounting, closing the LUKS device, and re-open and mount it:
```
# umount /mnt
# cryptsetup close cryptroot
# cryptsetup open /dev/sda2 cryptroot
# mount /dev/mapper/cryptroot /mnt
```

#### Backing up the LUKS header
Before you go putting your important data on your encrypted LUKS partition, you may want to backup the header. The header contains all the information needed to decrypt the drive (though that info cannot be accessed without your passphrase). If you do not create a backup, and your header gets corrupted, **you may permanently loose all your data!** To write the LUKS header to a file, use the following command:
```
# cryptsetup luksHeaderBackup /dev/sda5 --header-backup-file my_luks_header
```
This command does exactly what it says it does, so an explanation of the arguments is probably not needed here. Just make sure you put this file somewhere safe. Ideally on another drive somewhere.  
See the `cryptsetup` manpage for relevant warnings about header backups. In brief, there are none unless you change your passphrase. If you do, you have to make a new backup, or separately edit the backup, as someone with the backed up header could unlock your partition with the old passphrase otherwise.  
For more information on backups, see the `cryptsetup` FAQ, section 6

### Install Basic Arch System
At this point we have created an encrypted LUKS volume and mounted it to /mnt, so now we want to install a basic Arch Linux system on it.

#### Mirror List
For a basic mirror list of only Canadian https mirrors, do this:
```
# curl -L https://www.archlinux.org/mirrorlist/?country=CA&protocol=https&ip_version=4&use_mirror_status=on > /etc/pacman.d/mirrorlist
```
You will then have to open the file and remove the `#` from each mirror to activate it. Don't worry, there's only a few in Canada.

#### Packages
Run this command to install all the basic packages you will need for this guide (plus one or two useful utilities that you will probably just install later anyway):
```
# pacstrap /mnt base linux linux-firmware vim sudo man-db man-pages texinfo rng-tools cryptsetup efitools sbsigntools parted ntp grub efibootmgr tpm2-tools
```
If you prefer the packages listed on separate lines (eaiser to read), here they are, in no particular order:
```
base
linux
linux-firmware
vim
sudo
man-db
man-pages
texinfo
rng-tools
cryptsetup
efitools
sbsigntools
parted
ntp
grub
efibootmgr
tpm2-tools
```

#### Genfstab
Mount your efi partition at `/mnt/efi` (unmount it first if you had it mounted elsewhere before now). You will have to create that directory first too.  
For this guide, the future system's `/boot` directory will be bind mounted at `/efi/EFI/arch`:
```
# mount --bind /mnt/efi/EFI/arch /mnt/boot
```
With these mounts done, we can generate our `fstab` for the new system:
```
# genfstab -U /mnt > /mnt/etc/fstab
```
Double check the resulting file if you like.

#### Chroot
At this point we will [chroot](https://wiki.archlinux.org/index.php/Chroot) into the new system.  
```
# arch-chroot /mnt
```

#### From this point on, all sections assume you are inside the chroot, and file paths will be written accordingly!!

#### Timezone, Localization, and Network
See [Timezone](https://wiki.archlinux.org/index.php/Installation_guide#Time_zone), [Localization](https://wiki.archlinux.org/index.php/Installation_guide#Localization), and [Network](https://wiki.archlinux.org/index.php/Installation_guide#Network_configuration)

#### Bootloader
For this system we are using `grub` because it has features like TPM and Secure Boot support that we will need later. For now we will install grub manually, but later we will setup a pacman hook to do it automatically whenenver it gets updated.
```
# grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules=tpm
```
This installs grub in your efi partition, with the tpm module packaged into the core binary. It also creates an efi boot entry for "GRUB", which is also moved to the top of your boot order.

Edit `/etc/defaults/grub` to include the `tpm` module at the beginning of the `GRUB_PRELOAD_MODULES` setting then generate the config:

```
# grub-mkconfig -o /boot/grub/grub.cfg
```
This creates a grub config file that grub will read when it loads at boot. This inclues your menu entries (ones for Arch are auto-genrerated). See [this page](https://wiki.archlinux.org/index.php/GRUB#Configuration) for details.

#### Root Password
Don't forget to set your root password! Make sure it's a good one!
We won't cover creating any users here as it's not needed for a barebones bootable system. Technically the root password isn't either, but if you forget that leaves your system wide open.  
Just call `passwd` to set it, since you are already the root user.

### Unlocking LUKS with TPM 2.0

#### Sealing your LUKS passphrase with the TPM
Create a primary object under the owner heirachy.
```
# tpm2_creatprimary --heirachy=o --key-auth=someprivatekey --hash-algorithm=sha256 --key-algorithm=rsa4096:aes256cfb --key-context=somecontextfilepath --attributes=someattributes
```
Being explicit - some of these are default

Create Wilcard Polcy for Key.
```

```

Create a key under a the new primary key.
```
tpm2_create --parent-context=somecontextfilepath --parent-auth=someprivatekey --hash-algorithm=sha256 --key-algorithm=rsa --attributes=someattributes --sealing-input=alukspassphrase --policy=awildcardpolicyfile --key-context=somekeycontextfilepath
```


Current plan:
TPM sealed luks passkey is stored in TPM NV with flexible policy that is satisfied by another policy. Other Policy involves as many relevant PCRs as possible while maintaining convenience (might ignore bios settings?).
When a grub or kernel update is installed, other policy is updated (with auth key stored in encrypted disk) to a new temp policy that includes the secure boot PCR, and possibly the BIOS PCR (just not the ones related to grub, kernel, etc.), and the TPM Boot Counter +1 (only next boot allowed).
Initramfs script will check for:
1. Regular sealed key to unlock disk
2. Temp sealed key to unlock disk
3. Put up a password prompt (since we need a fallback)
  - On password fallback, show which PCR's changed, and ask if TPM seal should be updated
  - Would like to securely store the PCR values so that if we fall back to a password, the PCRs that changed can be shown to the user so they can decide if these changes were expected. Probably will store them as a salted hash value so the exact value of the PCR is not stored, but new salted hash can be generated.

Actual unlocking will be done via the regular `encrypt` hook, with the TPM unlock hook running first and creating a keyfile for the `encrypt` hook to read. Optional Re-seal will be handled by another hook that runs after the `encrypt` hook has unlocked the drive (since it needs the key in the drive to update the TPM policy.)

#### Unsealing your LUKS passphrase with the TPM automatically in initramfs

Initramfs Magic

#### Updating TPM seal on system update
Pacman hooks!

## Configuring Secure Boot
The first step is to take control of secure boot on your machine by replacing the secure boot certificates with your own, while retaining the default keys so you can still secure boot windows and get firmware updates.  
It is recommended to read at least the first portion of #1 in the secure boot resources section before proceeding to get a background on how secure boot works.
Another excellent resource is #2. Both are guides similar to this one. Feel free to use them instead of this one if they work for you. In particular, this guide only describes one pathway to configure secure boot (though it is the pathway that will hopefully work in the most cases). If it doesn't work for your hardware/firmware, the linked guides have other methods that may work.  
This section can be completed either using an Arch Linux live disk, or an already installed Arch Linux system. The reader is responsible for installing any needed packages, and for ensuring the security of their private keys (to be generated below).

### Generating New Secure Boot Keys
To generate a new Platofrm Key (PK), Key Exchange Key (KEK), and Database Key (db), you can use `openssl`. The examples in this guide will be using `openssl 1.1.1`, which is the latest Long Term Support release at the time of writing. Another option for the especially security consious is to use the TPM to generate the keys with it's hardware random number generator via the `tpm2-tss-engine` package.  

The following command will produce an RSA 2048 private key, and a matching public key certificate. You are welcome to try RSA 4096 for added security but not all UEFI firmware implementations support this, so your mileage may vary, and it might not be immediately obvious that it didn't work. (It appears that firmware for Lenovo Thinkpads going back at least to 2016 support RSA 4096).
```
# openssl req -new -x509 -newkey rsa:2048 -keyout PK.key -out PK.crt -days 3650 -nodes
```
`-new` tells openssl to create a new certificate request  
`-x509` tells openssl to actually create a certificate rather than just a request for one  
`-newkey rsa:2048` tells openssl to generate a new private key using RSA 2048  
`-keyout` and `-out` specify output files for the private key and certificate respectively  
`-days 3650` specifies how long the certificate should be valid for. Since we are putting this certificate in our computer firmware, we want it to last a while. Will you still have this computer in 10 years?  
`-nodes` this tells openssl to not encrpyt the private key. If you want to encrpyt it with a password, remove this option.  

When you run this command you will be prompted to enter some details about yourself as the issuer of the certificate. You can put as little or as much as you want here, but I would suggest at least setting the common name and/or organizaton. These can also be set from the above command with, for example, `-subj /CN=your common name/O=your org name/` if you do not want to do it interactively  
Unfortunately I can't find a good list of all values that can go in here. They are listed in [RFC 5280 section 4.1.2.4](https://tools.ietf.org/html/rfc5280#section-4.1.2.4), but the short names are not included there. You can find some of them on [this SO post](https://stackoverflow.com/questions/6464129/certificate-subject-x-509).  
As an example, this is the subject/issuer you'll find in the default PK on a lenovo thinkpad from 2016: `/C=JP/ST=Kanagawa/L=Yokohama/O=Lenovo Ltd./CN=Lenovo Ltd. PK CA 2012`

#### Generate the keys
Run the above command three times, generating a PK, KEK, and db key.
I did it like this:
```
# openssl req -new -x509 -newkey rsa:2048 -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd PK/" -keyout PK.key -out PK.crt -days 3650 -nodes

# openssl req -new -x509 -newkey rsa:2048 -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd KEK/" -keyout KEK.key -out KEK.crt -days 3650 -nodes

# openssl req -new -x509 -newkey rsa:2048 -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd db/" -keyout db.key -out db.crt -days 3650 -nodes
```

### Converting the certificates to EFI signature list format
The certificates generated are not in the format needed by the tools we will use to install them in the frimware. To fix this we will use some utilities from the `efitools` package. The version we are using here is 1.9.2.  
We want to convert our certificates to EFI Signature List (`.esl`) format. To do this, the following command is used:
```
# cert-to-efi-sig-list -g <your guid> PK.crt PK.esl
```
`-g` is used to provide a GUID to identify the owner of the certificate (you). If this is not provided, an all zero GUID will be used.  
`PK.crt` is the input certificate  
`PK.esl` is the output esl file.

#### Generate a GUID
In order to provide our own GUID for the certificate owner, we have to generate one. There is a multitude of ways to do this, but in this case a one line python script will do the trick:
```
# GUID=`python -c 'import uuid; print(str(uuid.uuid1()))'`
# echo $GUID > GUID.txt
```
The first line generates the GUID and assigns it to a shell variable called GUID, the second line echos the value into a text file so we can keep it beyond the current shell session.

#### Convert the certificates
Run the above command to convert each of the three certificates, also adding the GUID we just generated:
```
# cert-to-efi-sig-list -g $GUID PK.crt PK.esl
# cert-to-efi-sig-list -g $GUID KEK.crt KEK.esl
# cert-to-efi-sig-list -g $GUID db.crt db.esl
```

### Preserving the default KEK and db, and dbx entries
Since we want to be able to dual boot Windows 10, it is important that we preserve the default KEK, db, and dbx entries from Microsoft and the computer manufacturer. Maintaining Microsoft's keys will ensure that Windows can still boot, and maintaining the manufacturer keys will ensure we can still install things like EFI/BIOS updates, which are often distributed as EFI binaries signed by the manufactuer's key, that run on reboot to update the firmware. It is especially important that we preserve the dbx entries if we are keeping the Microsoft keys, as the dbx contains a black list of signed efi binaries (mostly all signed by Microsoft) that are not allowed to run, despite being signed by an certificate in the db (one of the Microsoft keys). "But I only need the db and dbx keys for this" you might be thinking. True, but if we do not keep the KEKs too, you cannot benefit from updates to the db and dbx issued by Microsoft or your computer manufacturer. Removing the manufacturer's PK does prevent them from issuing new KEKs, but this is much less likely, and if you want to take control of secure boot there is no way around replacing the PK, unless you have access to the private key it was made with.  
Finally, while most firmware has an option to restore factory default keys, if yours does not, you may want to keep these keys for that usecase too.

To preserve the existing keys, we will use another utility from `efitools` called `efi-readvar`. This utility runs in Linux user-space and can read efi secure variables such as the secure boot variables:
```
# efi-readvar -v PK -o original_PK.esl
```
`-v` specifies the efi variable to read
`-o` file to output the contents to (notice this is also in `.esl` format.)

#### Copy Original Keys
Run the above command for each of PK, KEK, db, and dbx
```
# efi-readvar -v PK -o original_PK.esl
# efi-readvar -v KEK -o original_KEK.esl
# efi-readvar -v db -o original_db.esl
# efi-readvar -v dbx -o original_dbx.esl
```

#### Append original keys to new keys
With the `.esl` file format, we can easily merge our new keys with the existing ones by simply concatenating the files:
```
# cat KEK.esl original_KEK.esl > all_KEK.esl
# cat db.esl original_db.esl > all_db.esl
```

### Signing the EFI signature list files
While we don't technically need to do this step, since the firmware will accept any keys in secure boot setup mode (we'll get to that later), it is more correct to use signed update files.  
If you want to add a KEK or db entry after secure boot is no longer in setup mode, you'll have to sign it with the next highest key so let's do that now as practice. The PK can sign itself, and is considered the root of trust, just like the root certificate from a certificate authority such as entrust or lets encrypt. The following command is used to sign the signature lists:
```
# sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth
```
`-k` specifies the private key for the certificate.  
`-c` specifies the certificate to sign with.  
`PK` is the EFI variable the output is intended for.  
`PK.esl` is the EFI signature list file to sign.  
`PK.auth` is the name of signed EFI signature list file, with a `.auth` extension indicating that it has an authentication header added.

#### Sign the files
Run the above command for each `.esl` file:
```
# sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth
# sign-efi-sig-list -k PK.key -c PK.crt all_KEK KEK.esl all_KEK.auth
# sign-efi-sig-list -k KEK.key -c KEK.crt db all_db.esl all_db.auth
# sign-efi-sig-list -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth
```
The PK signs itself, the PK also signs the KEKs, and our KEK (the only one we have the private key for) signs the db and dbx keys. Note that since we don't have anything to add to the dbx, we just sign the original list.  
Our db key is later used to sign EFI binaries and kernels that we want to boot, the KEK is used if we want to add new db entries, and the PK is used if we want to add new KEK entries.

### Installing the new Secure Boot Keys
The first step here is to put secure boot into setup mode by removing the current PK. This can be done from the BIOS setup utility, but beyond that, the exact steps differ greatly accross hardware. Typically there will be a security section, and in that, a secure boot section. This is where you would have turned secure boot off in order to install Arch Linux initially or to boot the live disk. Look for an option to put secure boot into setup mode, or an option to delete all secure boot keys. *If you see both, delete all keys*, as this often prevents certain issues with the tool we will be using (we saved all the old keys and will be replacing them anyway). Some firmware may require a firmware password to be set before these options are shown. Setup mode is on when there is no PK. Once a new PK is set, secure boot turns back to user mode, and any updates to any of the secure variables must by signed by the next highest key.  
Quick note: you may see a reference to `noPK.esl` or similar in the reference guides. This is an empty file signed with the PK that can be used to "update" the PK to nothing (remove the PK) while in user mode, thereby putting secure boot back into setup mode without entering the BIOS setup utility. This works because the PK can be updated in user mode as long as the update is signed by the current PK. Unless you are changing your keys often, you likely won't need this, but now you understand what it is for.

Once secure boot is in setup mode, we can use an `efitools` utility called `efi-updatevar` to replace each of the secure variables:
```
# efi-updatevar -f PK.auth PK
```
`-f` specifies the file to update the variable with. `PK.auth` is the efi signature list (signed in this example) that will be set on the variable. If you wan to use a .esl file here, you need to also add a `-e` before or after `-f`  
`PK` is the secure variable we want to update  
*NOTE:* This command as written will **replace** all the values in the variable. It is possible to instead append with `-a` but this seems to have problems on some firmware, while just replacing everything usually works, and in this case we added the old keys to ours and (ideally) cleared out all the secure variables before starting anyway. The reason it is ideal to clear out all the variables before starting is also because some firmware will not accept a replacement if there is a value present. Clearing all the keys and using the replacement command above appears to work in the most cases.

#### Install new secure boot keys
Run the above command for dbx, db, KEK, and PK, preferably in that order, but just make sure the PK is last so that we keep setup mode active.  
```
# efi-updatevar -f dbx.auth dbx
# efi-updatevar -f all_db.auth db
# efi-updatevar -f all_KEK.auth KEK
# efi-updatevar -f PK.auth PK
```
Since we signed our efi signature lists and created auth files we should theoretically be able to update the KEK, db, and dbx even after setting the PK (which takes us out of setup mode), but `efi-updatevar` seems to have trouble doing this. There are other tools that work better for updating with signed esl files (`.auth`) when secure boot is in user mode. For example `KeyTool`, also from `efitools` seems to work fairly well, however it is an efi binary so you have to reboot to use it (like your BIOS setup), which is more cumbersome and less scriptable than `efi-updatevar`.

### Conclusion
If you successfully completed all of the above sections, you now have your own keys added to secure boot, so you can start signing bootloaders and kernels with your db key!  
If you want to quickly test your handywork `efitools` supplies a `HelloWorld` efi binary that you can sign and try to boot into. Here's how you would do that, assuming your efi system patition is mounted at `/boot` (you'll have to install a package called `sbsigntools`, which you'll need to sign your kernel later anyway).
```
# mv /boot/EFI/Boot/bootx64.efi /boot/EFI/Boot/bootx64-prev.efi
# sbsign --key db.key --cert db.crt --output /boot/EFI/Boot/bootx64.efi /usr/share/efitools/efi/HelloWorld.efi
```
This will rename your current default boot entry to bootx64-prev.efi to you can restore it after the test, and then sign and copy HelloWorld.efi into the default efi boot location so it will automaticlly boot. After running this, reboot, and enter BIOS setup. Enable secure boot and save. When you exit setup it should try to boot the HelloWorld binary we just copied, and becasue we signed it, it should work. If it doesn't, then something went wrong up above.

## Signing your bootloader and kernel automatically on update
More Pacman hooks!

## Dual Booting with Windows without breaking Bitlocker on every bootloader update
Here we're going to do a little initramfs magic to add a boot entry for Windows in GRUB that doesn't involve chainloading, which would break TPM based Bitlocker every time GRUB is updated.  
Basically we are going to create an initramfs that sets the EFI BootNext variable and then reboots. This way, Windows always boots the same way - directly from the Windows Boot Manager, without even needing to know that GRUB exists. If Windows wants to update the boot manager, it already has a process for re-sealing the Bitlocker key in the TPM.

DONE!

## Resources
In addition to the resources linked in-line, these form the basis of the information contained within this guide, listed in no particular order.
### TPM Fundamentals
1. https://link.springer.com/book/10.1007%2F978-1-4302-6584-9
2. https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification/
3. https://trustedcomputinggroup.org/resource/pc-client-platform-tpm-profile-ptp-specification/
4. https://trustedcomputinggroup.org/resource/tpm-library-specification/
### Drive Encryption
1. https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LUKS_on_a_partition
2. https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#2-setup
3. https://manpages.debian.org/unstable/cryptsetup-bin/index.html
4. https://gitlab.com/cryptsetup/cryptsetup
5. https://wiki.archlinux.org/index.php/Dm-crypt
### TPM 2.0 Drive Key Sealing/Unlocking
1. https://tpm2-software.github.io/
2. https://github.com/tpm2-software/tpm2-tools/tree/master/man
3. https://medium.com/@pawitp/full-disk-encryption-on-arch-linux-backed-by-tpm-2-0-c0892cab9704
4. https://blog.dowhile0.org/2017/10/18/automatic-luks-volumes-unlocking-using-a-tpm2-chip/
5. https://threat.tevora.com/secure-boot-tpm-2/
### Secure Boot
1. http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html
2. https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide/Configuring_Secure_Boot
3. https://www.openssl.org/docs/man1.1.1/man1/openssl-req.html
4. https://manpages.debian.org/unstable/efitools/index.html
5. https://wiki.archlinux.org/index.php/Secure_Boot