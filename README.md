# Dual Booting Arch Linux and Windows 10 with Secure Boot and Encrypted Disks
So you want to dual boot Arch Linux and Windows 10, both with disk encryption. On Windows you have bitlocker turned on which encrpyts your disk without requiring a password on every boot. Then you disable secure boot to install Arch and now bitlocker is demanding that you either turn secure boot back on, or enter your recovery key each and every time you boot windows. Not ideal. This guide will help you take control of secure boot on your computer so that you can sign your Linux kernel and run it with secure boot turned on, as well as show you how to set up "bitlocker-like" disk encryption for your Linux partition (so you don't have to enter a password every time for Linux either). It is not for beginners, and expects a certain knowledge level of Linux, or at least an ability to look things up and learn as you go, just as with many other aspects of running Arch Linux as opposed to Ubuntu or similar "user friendly" distributions. While this guide attempts to include as many details as possible, it is far from exhaustive, and it is up to the reader to fill in the gaps.

## Before You Begin
You want to disable Windows Bitlocker before proceeding, as we will be making changes that will result in the TPM not releasing the keys needed to decrypt the disk automatically. Read on to understand what this means (in fact, it is strongly suggested that you read the entire guide and suggested reference material before you begin so you can do further research to answer any questions you might have). The actual procedure described in this guide should take about an hour if you already know what you are doing (because you read the guide through first or are otherwise already knowledgeable).  
For disk encryption on Linux, it is easier to setup before installing Linux, as it involves the creation of a new encrypted logical volume on top of a physical partition. Alternatively, you can take a backup, or use remaining free space on the disk temporarily. This guide will only cover encrypting a new Linux installation (it briefly runs through installing a barebones Arch Linux system).  
The beginning part of this guide assumes you are using a recent copy of the Arch Linux Live Disk. Once you have disabled secure boot and booted into the Arch Live Disk, install and start the following tools and services, as they are not included on the Live Disk and will be needed before we install the new system:
```
# pacman -Sy tpm2-tools tpm2-abrmd
# systemctl start tpm2-abrmd
```
Later we will turn secure boot back on, but we can't boot the live disk with it on.  

## How Bitlocker securely encrypts your drive without requiring a password at every boot.
Before diving into the how-to part of this guide, it is important underand on a basic level how Bitlocker and the hardware it depends on works in order to be able to setup a similar system for Linux. In short, Bitlocker works by storing your disk's encryption key in a hardware device called a Trusted Platform Module, or TPM, and the key is only released if the computer boots in a trusted configuration. 

### What is a TPM?
For a good overview of what a TPM is and what it can do, go read [this](https://en.wikipedia.org/wiki/Trusted_Platform_Module) and the first chapter of [this book](https://link.springer.com/book/10.1007%2F978-1-4302-6584-9) (or all of it really). That free book is arguably the single most useful resource for understanding the otherwise poorly docmented TPM. Note that here "poorly" is meant as in it is difficult to understand the documentation, not that every little detail isn't documented and specified (because it really is).  
The TPM can do a lot of things, but in the case of Bitlocker (as well as what we are about to do in Linux) it is used to cryptographically secure our disk encryption key in such a way that it can only be retrieved if the machine boots with the software we expect ([Platform Integrity](https://en.wikipedia.org/wiki/Trusted_Platform_Module#Platform_integrity)). This means that if someone where to try to boot from a live disk, or replace your bootloader or kernel ([evil maid attack](https://en.wikipedia.org/wiki/Evil_maid_attack)), the TPM will not release the disk encryption key.  
But wait, I read that Wikipedia page! It said there were ways extract secrets from TPMs! Yes, it's not a flawless system, but if you read further about it, the only people with the resources to carry out such attacks probably already have your data, if they even want it. Joe Smith who picks up your lost laptop bag on the train and takes it home won't be able to. Consider what your realistic [threat model](https://en.wikipedia.org/wiki/Threat_model) is, and if this is something you need to be concerned with, this guide isn't what you need. Instead, you may want to get yourself a giant magnet to repel any [$5 wrenches](https://xkcd.com/538/) that might be swung in your direction.

### How the TPM works
This section will really only scratch the surface, but it should give enough of an overview of how the TPM works that you will understand it's usage in this guide. Again, the free ebook linked above and at the end of this guide contains a wealth of information if you want to do a true deep dive like I did in order to write this guide. You won't find a better resource.  
Note that this guide assumes you are using a TPM that implements TPM 2.0, not TPM 1.2

#### Platform Configuration Registers
Platform Configuration Registers, or PCRs are the key feature of the TPM that we will be using. They are volatile memory locations within the TPM where the computer's firmware records "measurements" of the software that executes during the boot process (and possibly after boot as well). The values of the PCRs can be used to "seal" an encryption key (or another TPM object) with a policy that only allows the key to be released if the PCRs have the same value as they did when the polcy was created (which it is up to the user to determine is a trusted configuration). This is secure because unlike CPU registers, PCRs cannot be overritten or reset. They can only be "extended". All PCRs are initialized to zero at first power. Measurements are "extended" into the PCR by the firmware by passing the measurement to the TPM, which then "ORs" that data with the existing data in the PCR, takes a cryptograhic hash of the new value (usually sha1 or sha256) and then writes the hash digest to the PCR. "Measurements" are typically another cryptographic hash of the software binary or other data (such as configuration data) that is being measured.  
A minimum of 24 PCRs are required on a standard PC, though some TPMs may have more, or might have multiple "banks" of 24 that use different hash algorithms. 
Different PCRs contain measurements of different parts of the boot process. The Trusted Computing Group (TCG), the creators of the TPM specification, define which values should be extended into each PCR.  
It took me far too long to find this information unfortunately. It wasn't in the [TPM 2.0 Library Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/), or the [PC Client Platform TPM Profile Specification](https://trustedcomputinggroup.org/resource/pc-client-platform-tpm-profile-ptp-specification/). It can be found in the [PC Client Platform Firmware Profile 
Specification](https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification/). The TCG seem to have the unfortunate philosophy of "don't repeat yourself ever if at all possible" so you have to read parts of six documents to get the full picture of anything. To save you from all that, I have boiled the relevant parts down into the table below. This table is not exhastive, which is why nearly a quarter of the firmware specification deals directly with PCR usage. However it should give you a good idea of what values are measured into each PCR so that you know when to expect the values to change (such as when you update your BIOS, Kernel, or Boot Loader).  

PCR&nbsp;&nbsp;&nbsp;|Description
---------------------|-----------
0                    |UEFI BIOS Firmware, Embedded Device Drivers for non-removable hardware and other data from motherboard ROM.
1                    |UEFI BIOS Configuration Settings, UEFI Boot Entries, UEFI Boot Order and other data from motherboard NVRAM and CMOS that is related to the firmware and drivers measured into PCR 0.
2                    |UEFI Drivers and Applications for removable hardware such as adapter cards.<br>Eg. Most modern laptops have a wifi module and an m.2 ssd plugged into the motherboard rather than soldered on.
3                    |UEFI Variables and other configuration data that is managed by the code measured into PCR 2.
4                    |Boot Loader (eg. GRUB), and boot attempts.<br>If the first selected UEFI Boot Entry fails to load, that attempt is recorded, and so on until the UEFI BIOS is able to pass control successfully to a UEFI application (usually a boot loader), at which point the binary for that application is also measured into this PCR. 
5                    |Boot Loader Configuration Data, and possibly (the specification lists these as optional) the UEFI boot entry path that was used, and the GPT/Partition Table data for the drive that the boot loader was loaded from.
6                    |Platform Specific (your computer manufacturer can use this for whatever they want).
7                    |Secure Boot Policy<br>This includes all the secure boot varibles, such as PK, KEK, db, and dbx values. Also recorded here is the db value(s) used to validate the Boot Loader Binary, as well as any other binaries loaded with UEFI LoadImage().
8-15                 |Designated for use by the Operating System.<br>For the purposes of this guide, it is useful to note that GRUB extends measurements of it's configuration into PCR 8 rather than PCR 5. It also extends your kernel image and initramfs into PCR 9. See [this manual section](https://www.gnu.org/software/grub/manual/grub/grub.html#Measured-Boot) for details.
16                   |Debug PCR.<br>Note that this PCR can be reset manually without rebooting.
17-22                |No usage defined. Reserved for future use.
23                   |Application Support. This PCR is also resettable, like PCR 16, and can be used by the OS for whatever purpose it might need it for.

#### TPM Objects and Heirachies
Heirarchies are collections of TPM entities (such as keys or data) that are managed as a group. The TPM 2.0 Specificatoin defines three persistent heirarchies for different purposes: Endorsement, Platform, and Owner (sometimes refered to as "Storage") - plus a NULL heirarchy that is volatile. Each of these heirarchies is initialized with a large seed generated by the TPM that is never ever exposed outside the hardware. This seed is used to create primary keys at the top of each heirarchy. These keys are in turn used to encrypt child objects, wich can encrypt their children and so on, in a tree structure. Parents and all their children can be erased as a group if needed. Hierarchies are not limited to a single primary key, but can effectively have an unlimited number, though they cannot all be stored on the TPM. For this guide we will only be concerned with the Owner heirarchy, which is meant for end-users (though it really doesn't matter which you use, aside from the NULL heirarchy, the seed for which is regenerated on each boot).  

The main type of TPM Objects that this guide will deal with are primary keys, and child keys. Keys, like nearly all TPM entities, can have their access restricted in two main ways: Authorization Values (think passwords), and Policies. Policy based access control of TPM managed keys is how Bitlocker securely stores the disk encryption key and is able to retrieve it without having to ask for a password. It locks the disk encryption key with a policy that requires certain PCRs to have the same value during the current boot as they had when Bitlocker was enabled (which the user determined was a trusted boot configuration by turning on Bitlocker at that time.). In a similar manner, this guide will be storing a LUKS passphrase in the TPM locked with a policy based on PCR values. Policies are extremely powerful and can go far beyond matching PCR values, but you will have to read into that on your own. The only other policy feature we will be using is the Wildcard Policy. This is a policy that is satisfied by another policy (that must also satisfied) that is signed by an authorization key. Policies are immutable once created, so this allows for a more flexible policy. This allows us to seal the LUKS key once, but still update the PCR values that it is sealed against, since we can pass an updated second policy to the TPM when we update the BIOS or the Bootloader, among others.

#### How to interact with the TPM
To interact with the TPM, there is a set of open source linux user-space tools developed by Intel that are available in the official Arch repositories called `tpm2-tools`. It is a collection of command line programs to interact with the TPM via the `tpm2-tss` library to talk to the TPM, as well as the optional but strongly recommended `tpm2-abrmd` for access and resource management. Your best resource for these tools are the [manpages](https://github.com/tpm2-software/tpm2-tools/tree/master/man) in the git repo (or you can use `# man <tool>` but you have to know the name of the tool first). Anywhere you see a commandline tool used in this guide that starts with `tpm2_` in this guide, you can find that tool in `tpm2-tools`  

The version of `tpm2-tools` used to write this guide was `4.1.1`, however note that the manpages link is for the master branch. These tools are under continuous development and they have been known to change quite significatly between versions so take notice of which version you have, and select the appropriate release tag before reading any of the manpages.  

The `tpm2-tss` library is an implementation of the TCG's "TPM Software Stack" as specified in the TPM2 Library Specification linked to previously. This is an open source implemenation developed by Intel along side `tpm2-tools`. There is also a "competing" software stack by IBM (also open source), however I do not beleive the tools are compatible with it.

`tpm2-abrmd` is a user space TPM Access Broker and Resource Management Daemon. It does exactly what it says on the tin.  While it is true that the tools/tss can just access the TPM directly (the kernel makes it available as `/dev/tpm0`), this daemon allows for multiple programs to use the TPM at the same time without colliding. It also helps with certain commands by acting as buffer when we want to send the TPM more data than it can't otherwise handle all at once, which is more common that you think (TPM's have a very small minimum buffer size and most vendors don't bother to make it bigger).

## Installing Arch Linux on an Encrypted Disk// alongside Windows with Bitlocker
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
The next step is to set up disk encryption for your Linux partition. This will not be true full disk encryption because we will only be encrypting the Linux partition, but since our windows partition is encrypted with BitLocker, nearly the whole drive ends up being encrypted, just with different keys. We will not be encrypting the efi system partition, instead relying on secure boot signing and PCR measurements to prevent tampering. If you want an encrypted efi partition that is beyond the scope of this guide, but there are guides available that can help with this.  
For the purposes of this guide, we will only be encrpyting a single partition, with the assumption that your entire Linux system is on that partion, rather than having separate partitions for directories like `/home` which aren't necessary in most single-user cases.

#### dm-crypt and LUKS
`dm-crypt` is a Linux kernel module that is part of the kernel device mapper framework. If you are framiliar with LVM or software RAID, it uses the same base kernel functionality with the addition of encryption. `dm-crypt` supports multiple disk encrpytion methods and can even be stacked with LVM and/or RAID.  
Here we will be using LUKS encryption of a single volume mapped to a single real disk partition. LUKS stands for Linux Unified Key Setup and is the de facto standard for disk encryption on Linux, providing a consistent transferable system across distributions. For more information on LUKS and how it works, there are some great explanations at the [official project repository](https://gitlab.com/cryptsetup/cryptsetup).

#### Creating a LUKS encrypted Volume with `cryptsetup`
To help set everything up, we will use `cryptsetup`, which is the most commonly used cli for `dm-crypt` based disk encryption, as well as the reference implementation for LUKS. The version used to make this guide was 2.2.2  

##### Generating the LUKS MasterKey with the TPM (Optional)
The TPM has a built in [TRNG](https://en.wikipedia.org/wiki/Hardware_random_number_generator) that is potentially a better source of entropy than `/dev/random` and `/dev/urandom`. This is not to say that either of those are bad. In most cases they are actually very good sources of entropy! I'm not going to get into why you would want to use one or the other. That is left to you to research and determine. If you want, you can generate your LUKS master key with the TPM rather than `cryptsetup`'s default of `/dev/urandom`.  
To do this, we will first create a 100mb ramfs to work in, so that the key is never saved to a disk in the clear:
```
# mount -t ramfs -o 100m ramfs /path/to/your/chosen/mountpoint
```
You want to use ramfs rather than tmpfs because tmpfs can be swapped to the disk, while ramfs cannot. Further details on this are left to the reader.   

Then we will use `tpm2_getrandom` from `tpm2_tools` to generate 256 random bits as the key:
```
# tpm2_getrandom 32 > /path/to/your/chosen/mountpoint/mk.bin
```
Note the amount of data here is specified in Bytes, so 32*8=256 bits, which also happens to be the current default keysize for LUKS.  

Feed that into the command in the next section by adding the following flag:
```
--master-key-file /path/to/your/chosen/mountpoint/mk.bin
```

##### Format the partition

Assuming that your drive is already partitioned the way you want, the following command will format the given partition as a LUKS partition:
```
# cryptsetup luksFormat /dev/sda5 --verify-passphrase --verbose --iter-time 10000
```
`luksFormat` tells `cryptsetup` to format the given device as a LUKS device.  
`/dev/sda5` the device to format as a LUKS device.  
`--verify-passphrase` requires the passcode to unlock the LUKS partition to be entered twice, similar to other "comfirm your password" mechanisms.  
`--verbose` enables verbose mode.  
`--iter-time 10000` this manually sets the keyslot iteration time to 10 seconds.  
>Note on Iteration Time  
A keyslot iteration time of 10 seconds means that it will take 10 seconds (based on the speed of your current cpu) to unlock the drive using the passphrase. This is to compensate for a possibly weak passphrase and make it costly for an attacker to brute-force or dictionary attack it because it requires 10 seconds per attempt. The LUKS default is 1 second, in order to balance security and convenience. If you are confident in your passphrase you can choose to omit this and use the default (or set it to another value of your choice). For the configuration shown in this guide, the passphrase set here is considered a backup or fallback, and will not be used very often; thus making the 10 second wait time a nice feature that won't typically add to your boot time. Later we will be setting another passphrase that keeps the default 1 second, and is sealed into the TPM for automated unlocking on boot. Under most circumstances this second passphrase is the one that will be used, and it will be a randomly generated with the TPM's hardware random number generator to ensure that it would be impractical to brute force.  

There are a number of other options available surrounding how keys are generated, among other things, but in general the defaults will be more than enough for you unless you are using an older/less powerful computer or have specific requirements such as using something stronger than AES128 (With a keysize of 256 bits, aes-xts works out to AES128 level security).  
`cryptsetup --help` outputs the defaults that were compiled into your version of the tool. Mine for LUKS are `cipher: aes-xts-plain64, key size: 256 bits, passphrase hashing: sha256, RNG: /dev/urandom`.  
Do your own reading to determine which other settings you might want. The `cryptsetup` [FAQ](https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#2-setup) and [manpage](https://manpages.debian.org/unstable/cryptsetup-bin/cryptsetup.8.en.html) contain a wealth of information.

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
See the `cryptsetup` manpage for relevant warnings about header backups. In brief, there are none unless you change your passphrase. If you do, you have to make a new backup, or separately edit the backup, as someone with the backed up header could unlock your partition with the old passphrase otherwise. The header cannot decrypt anything without knowledge of the passphrase(s).  
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
# pacstrap /mnt base linux linux-firmware vim sudo man-db man-pages texinfo openssl cryptsetup efitools sbsigntools grub efibootmgr tpm2-tools tpm2-abrmd tpm2-tss-engine
```
If you prefer the packages listed on separate lines, here they are, in no particular order:
```
base
linux
linux-firmware
vim
sudo
man-db
man-pages
texinfo
openssl
cryptsetup
efitools
sbsigntools
grub
efibootmgr
tpm2-tools
tpm2-abrmd
tpm2-tss-engine
```
This package set will get you booting and doing everthing in this guide, but not a whole lot else. If you know what other packages you want, install them now (in particular, make sure you install something to allow you connect to a network or you'll have to boot the live disk again just to install more packages later)

#### Genfstab
Mount your efi partition at `/mnt/efi`. You will have to create that directory first.  
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

#### From this point on, it is assumed you are inside the chroot, and file paths will be written accordingly!!

#### Timezone, Localization, and Network
See [Timezone](https://wiki.archlinux.org/index.php/Installation_guide#Time_zone), [Localization](https://wiki.archlinux.org/index.php/Installation_guide#Localization), and [Network](https://wiki.archlinux.org/index.php/Installation_guide#Network_configuration)

#### Bootloader
For this system we are using `grub` because it has features like TPM and Secure Boot support that we will need later. For now we will install grub manually, but later we will setup a pacman hook to do it automatically whenenver it gets updated.
```
# grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules=tpm
```
This installs grub in your efi partition, with the tpm module packaged into the core binary. It also creates an efi boot entry for "GRUB", which is also moved to the top of your boot order.

Edit `/etc/default/grub` to include the `tpm` module at the beginning of the `GRUB_PRELOAD_MODULES` setting then generate the config:

```
# grub-mkconfig -o /boot/grub/grub.cfg
```
This creates a grub config file that grub will read when it loads at boot. This inclues your menu entries (ones for Arch are auto-genrerated). See [this page](https://wiki.archlinux.org/index.php/GRUB#Configuration) for details.

#### Root Password
Don't forget to set your root password! Make sure it's a good one!
We won't cover creating any users here as it's not needed for a barebones bootable system. Technically the root password isn't either, but if you forget that leaves your system wide open.  
Just call `passwd` to set it, since you are already the root user.

#### Enable tpm2-abrmd service
We installed and started this daemon on the live disk way back at the beginning of the guide. Enabling it now inside the chroot means systemd will automatically start it when we boot into our new system. 
```
systemctl enable tpm2-abrmd
```

## Unlocking LUKS Automatically with TPM 2.0

### Mount a Ramfs as a working directory
It's always a good idea to use a ramfs when generating keys. Refer above in the optional section about generating a master key to see how to mount a ramfs, or use the same one if you didn't unmount it. The following sections assume this ramfs as your working directory.

### Sealing a LUKS passphrase with the TPM

#### Generate a primary key
The primary key sits at the top of the TPM hierarchy and is used to encrypt it's child keys within the TPM. If the primary is compromised, so is every key under it.  
With that in mind, the best way to ensure nobody else can access and use your primary key is to not store it anywhere. How does that work? Primary keys are derived from the Heirachy Primary Seed (in this case, the Owner Primary Seed). The derivation function is deterministic. Given the same seed and the same key template, it can regenerate the same key every time. This means that the only thing we need to do is make sure our template is unique. We can do this by supplying some unique data only known to us during the creation of the primary key. This is sort of like generating the key with two seeds. We can then store the unique data in a secure location (such as a LUKS encrypted USB Flash Drive) so that only someone with access to that unique data can re-generate the primary key. **This unique data should be given the same care as a private key.**  
To generate the unique data, you can use the TPM's TRNG, or some other source of entropy of your choice. 

Generate the unique data with the TPM:
```
# tpm2_getrandom 32 > pkseed.bin
# printf `\x20\x00` > pkseedsize.bin
# cat pkseedsize.bin pkseed.bin > pkunique.dat
```
This will generate 32 random bytes with the TRNG, then create a 2-btye header to indicate the amount of data (32 bytes). This header is a UINT16 in little-endian byte order, which is why it is 0x2000, not 0x0020. Note that `printf`'s `\x` escape sequence only works for one byte, so we need it twice. `cat` is then used to contactenate the two parts into a single file.
You only need to store `pkunique.dat` somewhere safe. Also note that the file extensions are not required.


Generate the primary key with the unique data:
```
# tpm2_creatprimary --unique-data pkseed.bin --key-context pkcontext.ctx
```
`--key-context pkcontext.ctx` saves the key's context to a file for reference later. This context is only useful so long as the primary key is in the TPM's memory.  
There are many more options for this command, but in this case we are sticking to the defaults, which I will list below:
- Heirarchy: Owner
- Algorithm: `rsa2048:null:aes128cfb`
  - Many TPMs won't offer much better than this as the spec doesn't require it. Depending on which version of the spec your TPM conforms to, it may also have `aes256` but it is recommended to use algorithms with matching key strengths (`rsa2048`'s 112 bits considered close enough to `aes128`'s 128 bits). `rsa16384` would be required for 256 bit key strength to match `aes256`.
- Hash Algorithm: `sha256`
- Attributes: `restricted|decrypt|fixedtpm|fixedparent|sensitivedataorigin|userwithauth|noda`
- Authorization Key: null/empty password. This is ok because we aren't storing the key in the TPM, so the only want to get access to it, is to regenerate it with the unique data (which acts like sort of like an authorization key), and the seed from the Owner Hierarchy.
- Authorization Policy: also null. See above.

#### Generate the new LUKS passphrase just for the TPM
Next we need to create a new LUKS passphrase to use with the TPM. If you set the iteration time on your previous passphrase to 10 seconds, this is especially important to make sure your "normal" boot times are short.  
Again we can use the TPM's TRNG to generate a random key:
```
# tpm2_getRandom 32 > passphrase.bin
```
And then we can use the `cryptsetup`'s `luksAddKey` command:
```
# cryptsetup luksAddKey /dev/sda5 passphrase.bin
```
This command is pretty self explanitory. It will prompt you for your previous passphrase before adding the new key in keyslot 2 (A LUKS device can have up to 10 passphrases).

#### Create a flexible policy
Before we seal this new passphrase into the TPM under our primary key, we need to create a policy to seal it with, so that it can only be accessed if the policy is satisfied. Normally such a policy would involve the values of PCRs that are known to contain measurements of a trusted boot configuration (such as the new arch install we just created), however PCR values are inherently brittle. Whenver you update your bootloader, kernel, or BIOS, the PCR values will change. We would then have to re-seal the passphrase because an object's policy is immutable after it is created. To mitigate this issue, there is a special kind of policy that we can seal our pasphrase with called a wildcard policy. This is a policy that can only be satisfied by another policy that has been signed by an authorization key (and that policy must also be satisfied however it requires). This second policy is passed in at the time the sealing object is to be used (when our passphrase is to be unsealed and used to unlock the disk),  
Create Wilcard Policy for sealing object:
```
# tpm2_create 
# tpm2_startauthsession --policy-session -g sha256 -c pkcontext.ctx -S policysession.plss

```
#### Seal the LUKS passphrase with a new sealing object under the primary key
Create a sealing object under the new primary key.
```
tpm2_create --parent-context=somecontextfilepath --parent-auth=someprivatekey --hash-algorithm=sha256 --key-algorithm=rsa --attributes=someattributes --sealing-input=passphrase.bin --policy=awildcardpolicyfile --key-context=somekeycontextfilepath
```
#### Store the sealing object in the TPM NV Storage

### Need to reboot to get true PCR values for second policy....




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

### Unsealing your LUKS passphrase with the TPM automatically in initramfs

Initramfs Magic

### Updating TPM seal on system update
Pacman hooks!

## Configuring Secure Boot
The first step is to take control of secure boot on your machine by replacing the secure boot certificates with your own, while retaining the default keys so you can still secure boot windows and get firmware updates.  
It is recommended to read at least the first portion of [Rod's Guide to Controlling Secure Boot](http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html) before proceeding to get a background on how secure boot works.
Another excellent resource is [This Guide from the Gentoo Wiki](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide/Configuring_Secure_Boot). Both are guides similar to this one. Feel free to use them instead of this one if they work for you. In particular, this guide only describes one pathway to configure secure boot (though it is the pathway that will hopefully work in the most cases). If it doesn't work for your hardware/firmware, the linked guides have other methods that may work.  
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
This will rename your current default boot entry to bootx64-prev.efi so you can restore it after the test, and then sign and copy HelloWorld.efi into the default efi boot location so it will automaticlly boot. After running this, reboot, and enter BIOS setup. Enable secure boot and save. When you exit setup it should try to boot the HelloWorld binary we just copied, and becasue we signed it, it should work. If it doesn't, then something went wrong up above.

## Signing your bootloader and kernel automatically on update
More Pacman hooks!

## Dual Booting with Windows without breaking Bitlocker on every bootloader update
Here we're going to do a little initramfs magic to add a boot entry for Windows in GRUB that doesn't involve chainloading, which would break TPM based Bitlocker every time GRUB is updated.  
Basically we are going to create an initramfs that sets the EFI BootNext variable and then reboots. This way, Windows always boots the same way - directly from the Windows Boot Manager, without even needing to know that GRUB exists. If Windows wants to update the boot manager, it already has a process for re-sealing the Bitlocker key in the TPM.
I couldn't find a way to do this directly in GRUB. If you know how, please let me know or submit a PR!

## Resources
Most of these resources linked in-line. All of these form the basis for the information contained within this guide, listed in no particular order, but organized by general topic area. I've included links to online man pages and other documentation for most of the tools used.
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
