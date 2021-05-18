<!-- omit in toc -->
# Secure Booting Arch Linux Alongside Windows 10 with Encrpyted Disks

This guide started as my personal documentation of this process for my own reference, and grew to become the monstrosity you see below. I am **not** a security expert. I am a software developer with experience primarily in web development and this guide is the culmination of my own research into this topic and is by no means meant to impart any sort of sound security advice. It is up to you to determine if the setup described here is suitably secure for your needs. The [safeboot project has an excellent](https://safeboot.dev/threats/) page that describes all the types of attacks that they protect against and how they prevent them. You may well find their work to be more suitable to your needs. It is indisputably more secure, but at the cost of some convenience.

If something included in this guide is totally wrong, bad practice, or fundamentally insecure please open an issue, submit a pull request, or otherwise contact me. I welcome the feedback!

<!-- omit in toc -->
# Table of Contents

- [Introduction](#introduction)
- [Before You Begin](#before-you-begin)
- [How Bitlocker securely encrypts your drive without requiring a password at every boot](#how-bitlocker-securely-encrypts-your-drive-without-requiring-a-password-at-every-boot)
  - [What is a TPM?](#what-is-a-tpm)
  - [How the TPM works](#how-the-tpm-works)
    - [Platform Configuration Registers](#platform-configuration-registers)
    - [TPM Objects and Hierarchies](#tpm-objects-and-hierarchies)
    - [How to interact with the TPM](#how-to-interact-with-the-tpm)
- [Secure Boot and how it works](#secure-boot-and-how-it-works)
- [Overview (TLDR)](#overview-tldr)
  - [Secure Boot Process](#secure-boot-process)
  - [Encrypted Disk unlocked via TPM](#encrypted-disk-unlocked-via-tpm)
  - [Two-Factor TPM disk unlocking](#two-factor-tpm-disk-unlocking)
  - [What is not covered](#what-is-not-covered)
  - [Limitations](#limitations)
- [Installing Arch Linux on an Encrypted Disk alongside Windows with Bitlocker](#installing-arch-linux-on-an-encrypted-disk-alongside-windows-with-bitlocker)
  - [Pre Installation](#pre-installation)
  - [Setting up the Disk Encryption](#setting-up-the-disk-encryption)
    - [dm-crypt, LUKS, and cryptsetup](#dm-crypt-luks-and-cryptsetup)
    - [Format the partition](#format-the-partition)
    - [Open the LUKS partition](#open-the-luks-partition)
    - [Create the filesystem and mount it](#create-the-filesystem-and-mount-it)
    - [Backing up the LUKS header](#backing-up-the-luks-header)
  - [Install Basic Arch System](#install-basic-arch-system)
    - [Mirror List](#mirror-list)
    - [Packages](#packages)
    - [Genfstab](#genfstab)
    - [Chroot](#chroot)
    - [Timezone, Localization, and Network](#timezone-localization-and-network)
    - [Root Password](#root-password)
    - [Enable tpm2-abrmd service](#enable-tpm2-abrmd-service)
    - [Bootloader](#bootloader)
    - [Make the system bootable](#make-the-system-bootable)
    - [Reboot into your new Arch installation](#reboot-into-your-new-arch-installation)
- [Prepare a USB flash drive for TFA unlocking](#prepare-a-usb-flash-drive-for-tfa-unlocking)
- [Mount a Ramfs as a working directory](#mount-a-ramfs-as-a-working-directory)
- [Sealing your LUKS Passphrase with TPM 2.0](#sealing-your-luks-passphrase-with-tpm-20)
  - [Generate a primary key](#generate-a-primary-key)
    - [Generate the authorization value](#generate-the-authorization-value)
    - [Generate the primary key with the authorization value](#generate-the-primary-key-with-the-authorization-value)
  - [Add Authorization for Dictionary Attack Lockout](#add-authorization-for-dictionary-attack-lockout)
    - [Generate the DA Lockout authorization value](#generate-the-da-lockout-authorization-value)
    - [Set the DA Lockout authorization value](#set-the-da-lockout-authorization-value)
  - [Generate the new LUKS passphrase just for the TPM](#generate-the-new-luks-passphrase-just-for-the-tpm)
  - [Create a policy to seal the passphrase with](#create-a-policy-to-seal-the-passphrase-with)
    - [Create an access value for the policy authorization key](#create-an-access-value-for-the-policy-authorization-key)
    - [Create an authorization key for the policy](#create-an-authorization-key-for-the-policy)
      - [If you get an error here](#if-you-get-an-error-here)
    - [Store the policy authorization key in the TPM permanently](#store-the-policy-authorization-key-in-the-tpm-permanently)
    - [Get the authorization key's name](#get-the-authorization-keys-name)
    - [Create Wildcard Policy with the authorization key](#create-wildcard-policy-with-the-authorization-key)
  - [Seal the LUKS passphrase with a persistent sealing object under the primary key](#seal-the-luks-passphrase-with-a-persistent-sealing-object-under-the-primary-key)
    - [Create a sealing object under the primary key](#create-a-sealing-object-under-the-primary-key)
    - [Store the sealing object in the TPM NV Storage](#store-the-sealing-object-in-the-tpm-nv-storage)
  - [Creating an authorized policy to unseal the LUKS passphrase on boot](#creating-an-authorized-policy-to-unseal-the-luks-passphrase-on-boot)
    - [Create a temporary policy](#create-a-temporary-policy)
    - [Sign the Policy](#sign-the-policy)
    - [Copy the policy and its signature to the USB drive](#copy-the-policy-and-its-signature-to-the-usb-drive)
  - [Testing everything so far](#testing-everything-so-far)
    - [Create and sign the test policy](#create-and-sign-the-test-policy)
    - [Verify the policy](#verify-the-policy)
    - [Create a real auth session](#create-a-real-auth-session)
    - [Recreate the policy in the real auth session](#recreate-the-policy-in-the-real-auth-session)
    - [Unseal and test the passphrase](#unseal-and-test-the-passphrase)
- [Securing the boot process](#securing-the-boot-process)
  - [Taking Control of Secure Boot](#taking-control-of-secure-boot)
    - [Generating New Secure Boot Keys](#generating-new-secure-boot-keys)
      - [Generate the keys](#generate-the-keys)
    - [Generate a PGP key](#generate-a-pgp-key)
      - [Increase default `gpg-agent` KDF iterations](#increase-default-gpg-agent-kdf-iterations)
      - [Generate a new PGP keyring and key](#generate-a-new-pgp-keyring-and-key)
      - [Increase key expiry date](#increase-key-expiry-date)
      - [Encrypt the db key](#encrypt-the-db-key)
    - [Converting the certificates to EFI signature list format](#converting-the-certificates-to-efi-signature-list-format)
      - [Generate a GUID](#generate-a-guid)
      - [Convert the certificates](#convert-the-certificates)
    - [Preserving the default KEK and db, and dbx entries](#preserving-the-default-kek-and-db-and-dbx-entries)
      - [Copy Original Keys](#copy-original-keys)
      - [Append original keys to new keys](#append-original-keys-to-new-keys)
    - [Signing the EFI signature list files](#signing-the-efi-signature-list-files)
      - [Sign the files](#sign-the-files)
    - [Installing the new Secure Boot Keys](#installing-the-new-secure-boot-keys)
      - [Install new secure boot keys](#install-new-secure-boot-keys)
    - [Test your new secure boot keys](#test-your-new-secure-boot-keys)
  - [Securing the BIOS](#securing-the-bios)
  - [Securing grub](#securing-grub)
    - [Export the public portion of the PGP key](#export-the-public-portion-of-the-pgp-key)
    - [Configure grub to use the key](#configure-grub-to-use-the-key)
    - [Configure grub with a passphrase](#configure-grub-with-a-passphrase)
    - [Signing files for grub](#signing-files-for-grub)
- [Automating Everything](#automating-everything)
  - [Automating Early Boot Tasks with Initramfs](#automating-early-boot-tasks-with-initramfs)
    - [Arch Linux and mkinitcpio](#arch-linux-and-mkinitcpio)
      - [Install Hook](#install-hook)
      - [Runtime Hook](#runtime-hook)
    - [Adding the hooks to the initramfs](#adding-the-hooks-to-the-initramfs)
      - [tpm2_encrypt](#tpm2_encrypt)
      - [bitlocker_windows_boot](#bitlocker_windows_boot)
    - [Update the initramfs image with the new hooks](#update-the-initramfs-image-with-the-new-hooks)
    - [Update GRUB to include necessary kernel command line arguments](#update-grub-to-include-necessary-kernel-command-line-arguments)
  - [Automating Update and Install tasks with Pacman Hooks](#automating-update-and-install-tasks-with-pacman-hooks)
    - [Pacman hooks](#pacman-hooks)
    - [Install the hooks](#install-the-hooks)
    - [GRUB updates](#grub-updates)
    - [Signing kernel and initramfs](#signing-kernel-and-initramfs)
    - [Secure boot signing](#secure-boot-signing)
    - [tpm2-encrypt-create-temporary-policy](#tpm2-encrypt-create-temporary-policy)
    - [Trigger the hooks](#trigger-the-hooks)
- [Conclusion](#conclusion)
- [Resources](#resources)
  - [Security Fundamentals](#security-fundamentals)
  - [TPM](#tpm)
  - [Arch Installation](#arch-installation)
  - [Linux Boot Process](#linux-boot-process)
  - [Pacman Hooks](#pacman-hooks-1)
  - [Drive Encryption](#drive-encryption)
  - [Secure Boot](#secure-boot)
  - [Secure Grub](#secure-grub)

# Introduction

So you want to dual boot Arch Linux and Windows 10, both with disk encryption. On Windows you have bitlocker turned on which encrypts your disk without requiring a password on every boot. Then you disable secure boot to install Arch and now bitlocker is demanding that you either turn secure boot back on, or enter your recovery key each and every time you boot windows. Not ideal. This guide will help you take control of secure boot on your computer so that you can sign your Linux kernel and run it with secure boot turned on, as well as show you how to set up "bitlocker-like" disk encryption for your Linux partition (so you don't have to enter a password every time for Linux either). We'll even take it a step further and add a second factor to the unlock process by requiring data stored on a USB flash drive that you keep with you.  
It is not for beginners, and expects a certain knowledge level of Linux, or at least an ability to look things up and learn as you go, just as with many other aspects of running Arch Linux as opposed to Ubuntu or similar "user friendly" distributions. While this guide attempts to include as many details as possible, it is far from exhaustive, and it is up to you to fill in the gaps and make any adjustments that you deem necessary for your situation.

# Before You Begin

You want to disable Windows Bitlocker before proceeding, as we will be making changes that will result in the TPM not releasing the keys needed to decrypt the disk automatically. Read on to understand what this means (in fact, it is strongly suggested that you read the entire guide and suggested reference material before you begin so you can do further research to answer any questions you might have). The actual procedure described in this guide should only take an hour or two if you already know what you are doing (because you read the guide through first or are otherwise already knowledgeable).  
For disk encryption on Linux, it is easier to setup before installing Linux, as it involves the creation of a new encrypted logical volume on top of a physical partition. Alternatively, you can take a backup, or use remaining free space on the disk temporarily. This guide will only cover encrypting a new Linux installation (it briefly runs through installing a barebones Arch Linux system).  
The beginning part of this guide assumes you are using a recent copy of the Arch Linux Live Disk. Once you have disabled secure boot and booted into the Arch Live Disk, install and start the following tools and services, as they are not included on the Live Disk and will be needed before we install the new system:

```Shell
pacman -Sy tpm2-tools tpm2-abrmd

systemctl start tpm2-abrmd
```

Later we will turn secure boot back on, but we can't boot the live disk with it on.  

# How Bitlocker securely encrypts your drive without requiring a password at every boot

Before diving into the how-to part of this guide, it is important to understand on a basic level how Bitlocker and the hardware it depends on works in order to be able to setup a similar system for Linux. In short, Bitlocker works by storing your disk's encryption key in a hardware device called a Trusted Platform Module, or TPM, and the key is only released if the computer boots in a trusted configuration.

## What is a TPM?

For a good overview of what a TPM is and what it can do, go read [this](https://en.wikipedia.org/wiki/Trusted_Platform_Module) and the first chapter of [this book](https://link.springer.com/book/10.1007%2F978-1-4302-6584-9) (or all of it really). That free book is arguably the single most useful resource for understanding the otherwise poorly documented TPM. Note that here "poorly" is meant as in it is difficult to understand the documentation, not that every little detail isn't documented and specified (because it really is).  
The TPM can do a lot of things, but in the case of Bitlocker (as well as what we are about to do in Linux) it is used to cryptographically secure our disk encryption key in such a way that it can only be retrieved if the machine boots with the software we expect ([Platform Integrity](https://en.wikipedia.org/wiki/Trusted_Platform_Module#Platform_integrity)). This means that if someone where to try to boot from a live disk, or replace your bootloader or kernel ([evil maid attack](https://en.wikipedia.org/wiki/Evil_maid_attack)), the TPM will not release the disk encryption key.  
"But wait, I read that Wikipedia page! It said there were ways extract secrets from TPMs!" Yes, it's not a flawless system, but if you read further about it, the only people with the resources to carry out such attacks probably already have your data, if they even want it. Joe Smith who picks up your lost laptop bag on the train and takes it home won't be able to. Consider what your realistic [threat model](https://en.wikipedia.org/wiki/Threat_model) is, and if this is something you need to be concerned with, this guide isn't what you need. Instead, you may want to get yourself some sort of force field to repel any [$5 wrenches](https://xkcd.com/538/) that might be swung in your direction.

## How the TPM works

This section will really only scratch the surface, but it should give enough of an overview of how the TPM works that you will understand it's usage in this guide. Again, the free ebook linked above contains a wealth of information if you want to do a true deep dive. You probably won't find a better resource.  
Note that this guide assumes you are using a TPM that implements TPM 2.0, not TPM 1.2

### Platform Configuration Registers

Platform Configuration Registers, or PCRs are the key feature of the TPM that we will be using. They are volatile memory locations within the TPM where the computer's firmware records "measurements" of the software that executes during the boot process (and possibly after boot as well). The values of the PCRs can be used to "seal" an encryption key (or another TPM object) with a policy that only allows the key to be released if the PCRs have the same value as they did when the policy was created (which is up to the user to determine is a trusted configuration). This is secure because unlike CPU registers, PCRs cannot be overwritten or reset. They can only be "extended". All PCRs are initialized to zero at first power. Measurements are "extended" into the PCR by the firmware by passing the measurement to the TPM, which then "ORs" that data with the existing data in the PCR, takes a cryptographic hash of the new value (usually sha1 or sha256) and then writes the hash digest to the PCR. "Measurements" are typically another cryptographic hash of the software binary or other data (such as configuration data) that is being measured.  
A minimum of 24 PCRs are required on a standard PC, though some TPMs may have more, or might have multiple "banks" of 24 that use different hash algorithms.
Different PCRs contain measurements of different parts of the boot process. The Trusted Computing Group (TCG), the creators of the TPM specification, define which values should be extended into each PCR.  
It took me far too long to find this information unfortunately. It wasn't in the [TPM 2.0 Library Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/), or the [PC Client Platform TPM Profile Specification](https://trustedcomputinggroup.org/resource/pc-client-platform-tpm-profile-ptp-specification/). It can be found in the [PC Client Platform Firmware Profile
Specification](https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification/). The TCG seem to have the unfortunate philosophy of "don't repeat yourself ever if at all possible" so you have to read parts of multiple documents to get the full picture of anything. To save you from all that, the relevant parts have been boiled down into the table below. This table is not exhaustive, which is why nearly a quarter of the firmware specification deals directly with PCR usage. However it should give you a good idea of what values are supposed to be measured into each PCR so that you know when to expect the values to change (such as when you update your BIOS, Kernel, or Bootloader).  

PCR&nbsp;&nbsp;&nbsp;|Description
---------------------|-----------
0                    |UEFI BIOS Firmware, Embedded Device Drivers for non-removable hardware and other data from motherboard ROM.
1                    |UEFI BIOS Configuration Settings, UEFI Boot Entries, UEFI Boot Order and other data from motherboard NVRAM and CMOS that is related to the firmware and drivers measured into PCR 0.
2                    |UEFI Drivers and Applications for removable hardware such as adapter cards (including graphics cards).<br>Eg. Many modern laptops have a wifi module and an m.2 ssd plugged into the motherboard rather than soldered on.
3                    |UEFI Variables and other configuration data that is managed by the code measured into PCR 2.
4                    |Boot Loader (eg. GRUB), and boot attempts.<br>If the first selected UEFI Boot Entry fails to load, that attempt is recorded, and so on until the UEFI BIOS is able to pass control successfully to a UEFI application (usually a boot loader), at which point the binary for that application is also measured into this PCR.
5                    |Boot Loader Configuration Data, and possibly (the specification lists these as optional) the UEFI boot entry path that was used, and the GPT/Partition Table data for the drive that the boot loader was loaded from.
6                    |Platform Specific (your computer manufacturer can use this for whatever they want).
7                    |Secure Boot Policy<br>This includes all the secure boot variables, such as PK, KEK, db, and dbx values, as well as whether secure boot is on or off (why turning it off breaks bitlocker). Also recorded here is the db value(s) used to validate the Boot Loader Binary, as well as any other binaries loaded with UEFI LoadImage().
8-15                 |Designated for use by the Operating System.<br>For the purposes of this guide, it is useful to note that GRUB extends measurements of it's configuration into PCR 8 rather than PCR 5. It also extends your kernel image, initramfs, and any other loaded files into PCR 9. See [this manual section](https://www.gnu.org/software/grub/manual/grub/grub.html#Measured-Boot) for details.
16                   |Debug PCR.<br>Note that this PCR can be reset manually without rebooting.
17-22                |No usage defined. Reserved for future use.
23                   |Application Support. This PCR is also resettable, like PCR 16, and can be used by the OS for whatever purpose it might need it for.

### TPM Objects and Hierarchies

The free book "A Practical guide to TPM 2.0" linked to earlier explains this quite well:
>A hierarchy can be thought of as having parent and child keys, or ancestors and descendants. All parent keys are storage keys, which are encryption keys that can wrap (encrypt) child keys. The storage key thus protects its children, offering secrecy and integrity when the child key is stored outside the secure hardware boundary of the TPM. These storage keys are restricted in their use. They can’t be used for general decryption, which could then leak the child’s secrets.  
>The ultimate parent at the top of the hierarchy is a primary key. Children can be storage keys, in which case they can also be parents. Children can also be non-storage keys, in which case they’re leaf keys: children but never parents.

The TPM 2.0 Specification defines three persistent hierarchies for different purposes: Endorsement, Platform, and Owner (sometimes referred to as "Storage") - plus a NULL hierarchy that is volatile. Each of these hierarchies is initialized with a large seed generated by the TPM that is never ever exposed outside the hardware. This seed is used to derive primary keys at the top of each hierarchy using a deterministic key derivation function that uses the seed plus a public template. Unless the seed is reset, the same template will always produce the same key, allowing for primary keys to be re-generated as needed. For this guide we will only be concerned with the Owner hierarchy, which is meant for end-users.  
The main types of TPM Objects that this guide will deal with are primary keys, child keys, and sealing objects. Keys, like nearly all TPM entities, can have their access restricted in two main ways: Authorization Values (think passwords), and Policies. Policy based access control of TPM managed keys is how Bitlocker securely stores the disk encryption key and is able to retrieve it without having to ask for a password. It locks the disk encryption key with a policy that requires certain PCRs to have the same value during the current boot as they had when Bitlocker was enabled (which the user determined was a trusted boot configuration by turning on Bitlocker at that time.). In a similar manner, this guide will be storing a LUKS passphrase in the TPM locked with a policy based on PCR values. Policies are extremely powerful and can go far beyond matching PCR values, but you will have to read into that on your own. The only other policy feature we will be using is the so-called Wildcard Policy. This is a policy that is satisfied by another policy (that must also satisfied) that is signed by an authorization key. Policies are immutable once created, so this allows for a more flexible policy. This allows us to seal the LUKS key once, but still update the PCR values that it is sealed against, since we can pass an updated second policy to the TPM when we update the BIOS or the Bootloader, among others.

### How to interact with the TPM

To interact with the TPM, there is a set of open source linux user-space tools originally developed by [Intel](https://software.intel.com/content/www/us/en/develop/blogs/tpm2-software-stack-open-source.html) that are available in the official Arch repositories called `tpm2-tools`. It is a collection of command line programs to interact with the TPM via the `tpm2-tss` library to talk to the TPM, as well as the optional but strongly recommended `tpm2-abrmd` for access and resource management. Your best resource for these tools are the [manpages](https://github.com/tpm2-software/tpm2-tools/tree/master/man) in the git repo (or you can use `man <tool>` but you have to know the name of the tool first). Anywhere you see a command line tool used in this guide that starts with `tpm2_`, you can find that tool in `tpm2-tools`  

The version of `tpm2-tools` used to write this guide was `4.1.1`, however note that the manpages link is for the master branch. These tools are under continuous development and they have been known to change quite significantly between major versions so take notice of which version you have, and select the appropriate release tag before reading any of the manpages.  

The `tpm2-tss` library is an implementation of the TCG's "TPM Software Stack" as specified in the TPM2 Library Specification linked to previously. This is an open source implementation developed originally by Intel and Infineon along side `tpm2-tools`. There is also a "competing" software stack by IBM (also open source), however `tpm2-tools` are not compatible with it. The version of `tpm2-tss` used in this guide is `2.3.2`

`tpm2-abrmd` is a user space TPM Access Broker and Resource Management Daemon. It does exactly what it says on the tin. While it is true that the tools/tss can just access the TPM directly (the kernel makes it available as `/dev/tpm0`), this daemon allows for multiple programs to use the TPM at the same time without colliding, among other helpful functions. It also provides extended session support when creating policies. The version used in this guide is `2.3.1`.  
The kernel has a built in resource manager at `/dev/tpmrm0` but it is not as fully featured as the userspace one at this point in time.

# Secure Boot and how it works

Secure Boot is a UEFI system that prevents the execution of unsigned EFI binaries, such as OS bootloaders (GRUB). It does this by maintaining a certificate registry that each EFI binary's signature is checked against. If there is no match then it won't be executed, thereby providing some level of certainty that binaries running are "trusted" and establishing the start of a chain of trust that can extend all the way to the running operating system. That trust is unfortunately somewhat relative though. The reason for this is that nearly every computer in the world comes with Microsoft's Secure Boot keys pre-installed. These keys are controlled by Microsoft and used to sign Windows bootloaders as well as firmware for plugin cards such as graphics cards, but they have also been used to sign other EFI binaries such as one called `shim` which can effectively allow any other EFI binary to run without having to be signed by Microsoft (though this does require physical presence to install an alternate certificate that `shim` will use to verify signatures, making it a limited attack vector). It is also worth noting that `shim` is not malicious in nature, and was signed to allow Linux distributions to work with secure boot without users having to go through the process you will see below to install their own keys in the UEFI certificate registry. `shim` just has the unfortunate side effect of creating a security hole under certain threat models due to the way it works. Some newer versions have worked to address these issues though.

# Overview (TLDR)

Now that we have covered secure boot, as well as the fundamentals of what a TMP is and how Bitlocker uses it, lets walk through what this guide will show you what the guide will setup at a high level.  
The one sentence version:
>The goal is to create a system that provides reasonable confidence that the computer is booting in a "trusted" configuration, and unlock the encrypted disk automatically using the TPM if that is the case.

This section was written after the guide was mostly complete, and while every effort was made to ensure it can be understood without reading the rest of the guide, this section barely scratches the surface, and the following sections provide lots of background information about everything used here.

## Secure Boot Process

We want to secure the boot process as much as possible from tampering. This goes beyond the UEFI feature called Secure Boot, which is only one link in the chain of trust. Secure Boot can only prevent binaries loaded directly with the EFI LoadImage() and StartImage() methods from running. In our case, this will be the GRand Unified Bootloader (GRUB), which then loads the Linux Kernel in it's own way without those methods. To continue the chain of trust, grub contains it's own method to verify the files it loads (including the kernel) with PGP signatures. It is possible to then have the linux kernel check for signatures on kernel modules it loads, but this third step is not something we will be doing here. All the modules (except those compiled into the kernel image or initramfs, which are already verified by GRUB) are stored on the encrypted disk which is considered to be trusted, and the integrity of all official arch packages are verified by PGP signature after they are downloaded.

## Encrypted Disk unlocked via TPM

The disk will be encrypted with LUKS, and unlocked automatically with a passphrase stored in the TPM that can only be unlocked if PCRs contain the expected values. The disk will not unlock if any of the PCR values are different, meaning that something in the boot sequence has changed, such as someone with physical access using shim to bypass secure boot, or replacing your kernel image with a malicious one. The TPM policy checks on the PCR values are separate from the checks done by secure boot and grub, meaning an attacker would have to bypass both systems to accomplish a boot time attack.

## Two-Factor TPM disk unlocking

Having the disk unlock automatically in the manner described so far is fairly secure, but it would also unlock for anyone who might pickup our machine if we were to lose it, or who otherwise has physical access to it. This leaves only our linux user password and other software access controls between such a person and our data. To mitigate this we can add another factor to the disk unlock. The signed TPM policies we will be creating can be stored on a USB drive that you keep with you. To unlock the disk automatically you'll need to have the usb drive connected to your machine. We will also be storing half of the authorization value needed to sign new TPM policies on this drive (and the other half inside the encrypted disk) so the drive will also be needed whenever the TPM policy needs to be refreshed, such as after a kernel or grub update.

## What is not covered

As mentioned, the linux kernel will not be configured to require signed kernel modules, nor will the root user to be de-privileged with [lockdown mode](https://mjg59.dreamwidth.org/55105.html) or any other linux hardening tricks. In fact, this guide only focuses on securing the boot process and securing the data on the disk at rest. Once the system has booted and the disk unlocked (the key for which is stored in kernel-only memory), the security of the system is left to the kernel, and the programs that run on it (eg. a tty login prompt or display manager, plus file system access controls, etc).

## Limitations

All digital security systems lie somewhere on a spectrum between complete paranoia and a complete lack of security. You have to decide where on the spectrum you want to fall. Ultimately, "transparent" or "hands off" security systems like the setup described here in this guide that automatically unlock your encrypted disk will likely never be as secure as more opaque alternatives (though they can come close). You sacrifice some security to convenience. This comes down to determining what your real threat model actually is, and then determining how secure you actually need your computer to be and what attack vectors you need to protect against. If you just used LUKS on it's own and typed in a passphrase at every boot it is very likely that would be more secure (assuming a very strong passphrase and a secured boot chain of trust), but it would certainly be less convenient to have to type in two different strong/long passwords just to get into your computer (the second being your linux user login).
Implementing sleep, suspend, or hibernate would be difficult to do securely with this setup and is not covered in any way. That said, it is recommended to use a swapfile rather than a separate partition for swap, as this will keep the contents inside your encrypted disk. If you would rather use a partition, look into `crypttab` for a way to encrypt your swap and mount it automatically.

# Installing Arch Linux on an Encrypted Disk alongside Windows with Bitlocker

This guide wasn't originally going to include Arch Installation steps, but it is easiest to set up disk encryption while doing a fresh install. Only steps that are not part of a typical install will be covered in detail. Everything else will be listed in brief only. See the [Official Install Guide](https://wiki.archlinux.org/index.php/Installation_guide) for details. Further, these steps will only install the bare minimum needed to boot Arch and do everything outlined in this guide.

*If you already have a running Arch system you may need to do a backup and then re-install everything anyway, unless you can find a way to do an [in-place conversion to LUKS](https://unix.stackexchange.com/questions/444931/is-there-a-way-to-encrypt-disk-without-formatting-it). If you do, just check the list of packages to install below and make sure you aren't missing any, then skip ahead to the end of this section where we configure grub with a few extra modules and options.*

## Pre Installation

See [Pre Installation](https://wiki.archlinux.org/index.php/Installation_guide#Pre-installation).
Stop at *Partition the Disks* and come back.  
For the purposes of this guide, it is assumed you have already partitioned the drive under Windows.  
Assumptions:

- Windows and Linux will reside on separate partitions on the same disk, with a shared EFI system partition.
- You have already installed Windows, and then used Windows disk manager to shrink `C` and create a new unformatted partition for Linux.
  - When installing windows, you probably want to make sure your EFI system partition is larger than the default of 100MB, as we will be putting our kernel image and other files in the EFI partition since the root partition will be encrypted. 500MB will give you lots of room, but 200MB is fine if disk space is limited. Check [this superuser answer](https://superuser.com/a/1308330) for instructions on how to create a larger EFI partition during Windows installation. You can probably do the same thing with a linux live disk before installing Windows too.

Installing Windows first is suggested as Windows is a lot pickier about drive layout and partition locations (and will happily bulldoze whatever it finds that isn't the way it wants if you aren't careful with the installer), but you are welcome to do it however you want.
An example partition scheme after doing this might be the following:

- /dev/sda1 - MS Recovery
- /dev/sda2 - EFI
- /dev/sda3 - MS Reserved
- /dev/sda4 - Windows C
- /dev/sda5 - Arch Linux / *- to be formatted below*

We will be using this example partition map in the below commands. **Make sure you modify them to suit your system.**

## Setting up the Disk Encryption

The next step is to set up disk encryption for your Linux partition. This will not be true *full disk* encryption because we will only be encrypting the Linux partition, but since our windows partition is encrypted with BitLocker, nearly the whole drive ends up being encrypted, just with different keys. We will not be encrypting the efi system partition, instead relying on secure boot signing and PCR measurements to prevent tampering. If you want an encrypted efi partition that is beyond the scope of this guide, but there are guides available that can help with this.  
For the purposes of this guide, we will only be encrypting a single partition, with the assumption that your entire Linux system is on that partition, rather than having separate partitions for directories like `/home` which aren't necessary in most single-user cases.

### dm-crypt, LUKS, and cryptsetup

`dm-crypt` is a Linux kernel module that is part of the kernel device mapper framework. If you are familiar with LVM or software RAID, it uses the same base kernel functionality with the addition of encryption. `dm-crypt` supports multiple disk encryption methods and can even be stacked with LVM and/or RAID.  
Here we will be using LUKS encryption of a single volume mapped to a single real disk partition. LUKS stands for Linux Unified Key Setup and is the de facto standard for disk encryption on Linux, providing a consistent transferable system across distributions. For more information on LUKS and how it works, there are some great explanations at the [official project repository](https://gitlab.com/cryptsetup/cryptsetup).  
To help set everything up, we will use `cryptsetup`, which is the most commonly used cli for `dm-crypt` based disk encryption, as well as the reference implementation for LUKS. The version used to make this guide was 2.2.2  

### Format the partition

Assuming that your drive is already partitioned the way you want, the following command will format the given partition as a LUKS partition:

```Shell
cryptsetup luksFormat /dev/sda5 --type luks2 --verify-passphrase --verbose --iter-time 10000
```

- `luksFormat` tells `cryptsetup` to format the given device as a LUKS device.  
- `/dev/sda5` is the device to format as a LUKS device.  
- `--type luks2` tells cryptsetup to use LUKS2 formatting.
  - LUKS2 has a different more extensible header format (and also a redundant header elsewhere on the drive to protect against corruption), however the primary reason for using it here is that it replaces the PBKDF2 key derivation of LUKS1 with Argon2 which is memory hardened against certain kinds of GPU based brute force attacks. You can learn more at the project [FAQ section on LUKS2](https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#10-luks2-questions).
- `--verify-passphrase` requires the passcode to unlock the LUKS partition to be entered twice, similar to other "confirm your password" mechanisms.  
- `--verbose` enables verbose mode.  
- `--iter-time 10000` this manually sets the keyslot iteration time to 10 seconds.  
  - A keyslot iteration time of 10 seconds means that it will take 10 seconds (based on the speed of your current cpu) to unlock the drive using the passphrase. This is to compensate for a possibly weak passphrase and make it costly for an attacker to brute-force or dictionary attack it because it requires 10 seconds per attempt. The LUKS default is 2 seconds, in order to balance security and convenience. If you are confident in your passphrase you can choose to omit this and use the default (or set it to another value of your choice). For the configuration shown in this guide, the passphrase set here is considered a backup or fallback, and will not be used very often; thus making the 10 second wait time a nice feature that won't typically add to your boot time. Later we will be setting another passphrase that keeps the default 2 seconds, and is sealed into the TPM for automated unlocking on boot. Under most circumstances this second passphrase is the one that will be used, and it will be a randomly generated to ensure it has enough entropy that it would be impractical to brute force.

There are a number of other options available surrounding how keys are generated, among other things, but in general the defaults will be more than enough for you unless you are using an older/less powerful computer or have specific requirements such as using something stronger than AES128 (With a key size of 256 bits, aes in xts mode works out to AES128, as xts operates on a pair of keys).  
`cryptsetup --help` outputs the defaults that were compiled into your version of the tool.  
Mine for LUKS are:  
`cipher: aes-xts-plain64, key size: 256 bits, passphrase hashing: sha256, RNG: /dev/urandom`.  
Do your own reading to determine which other settings you might want. The `cryptsetup` [FAQ](https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#2-setup) and [manpage](https://manpages.debian.org/unstable/cryptsetup-bin/cryptsetup.8.en.html) contain a wealth of information.

### Open the LUKS partition

After formatting the partition, we want to open it so that we can create the filesystem and mount it for writing. To open our encrypted LUKS partition, we use the following command:

```Shell
cryptsetup open /dev/sda5 cryptroot
```

- `open` tells `cryptsetup` we want to open a LUKS device.  
- `/dev/sda5` is the LUKS device we want to open.  
- `cryptroot` is the name we want to map the LUKS device to.
  - This can be any name you want. It will be made available at `/dev/mapper/cryptroot` (or whatever name you gave it).

Running the command as above will prompt you for your passphrase, after which the LUKS device will be mapped as specified.

### Create the filesystem and mount it

This part happens exactly like it would for a regular partition, except you are pointing at a different device in `/dev`

```Shell
mkfs.ext4 /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
```

At this point you may want to quickly verify that everything is working by unmounting, closing the LUKS device, and re-open and mount it:

```Shell
umount /mnt

cryptsetup close cryptroot

cryptsetup open /dev/sda5 cryptroot

mount /dev/mapper/cryptroot /mnt
```

### Backing up the LUKS header

Before you go putting your important data on your encrypted LUKS partition, you may want to backup the header. The header contains all the information needed to decrypt the drive (though that info cannot be accessed without your passphrase). If you do not create a backup, and your header gets corrupted, **you may permanently loose all your data!** To write the LUKS header to a file, use the following command:

```Shell
cryptsetup luksHeaderBackup /dev/sda5 --header-backup-file my_luks_header
```

This command does exactly what it says it does, so an explanation of the arguments is probably not needed here. Just make sure you put this file safe on another drive somewhere.  
See the `cryptsetup` manpage for relevant warnings about header backups. In brief, there are none unless you change your passphrase. If you do, you have to make a new backup, or separately edit the backup, as someone with the backed up header could unlock your partition with the old passphrase otherwise. Remember, the header cannot decrypt anything without knowledge of the passphrase(s) contained in it.  
For more information on backups, see the `cryptsetup` FAQ, section 6

## Install Basic Arch System

At this point we have created an encrypted LUKS volume and mounted it to /mnt, so now we want to install a basic Arch Linux system on it.

### Mirror List

For a basic mirror list of only Canadian https mirrors, do this:

```Shell
curl -L https://www.archlinux.org/mirrorlist/?country=CA&protocol=https&ip_version=4&use_mirror_status=on > /etc/pacman.d/mirrorlist
```

You will then have to open the file and remove the `#` from each mirror to activate it. Don't worry, there's only a few in Canada. Adjust as needed for your geographic location on [this page](https://www.archlinux.org/mirrorlist/).

### Packages

Run this command to install all the basic packages you will need for this guide (plus one or two useful utilities that you will probably just install later anyway):

```Shell
pacstrap /mnt base linux linux-firmware vim sudo man-db man-pages texinfo openssl cryptsetup efitools sbsigntools grub efibootmgr tpm2-tools tpm2-abrmd
```

If you prefer the packages listed on separate lines, here they are, in no particular order:

```Text
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
```

This package set will get you booting and doing everything in this guide, but not a whole lot else. If you know what other packages you want, install them now (in particular, make sure you install something to allow you connect to a network such as `dhcpd` or you'll have to boot the live disk again just to install more packages later!)

### Genfstab

Mount your efi partition at `/mnt/efi`. You will have to create that directory first.  
For this guide, the future system's `/boot` directory will be bind mounted at `/efi/EFI/arch` as found in [this wiki section](https://wiki.archlinux.org/index.php/EFI_system_partition#Alternative_mount_points):

```Shell
mount --bind /mnt/efi/EFI/arch /mnt/boot
```

With these mounts done, we can generate our `fstab` for the new system:

```Shell
genfstab -U /mnt > /mnt/etc/fstab
```

Double check the resulting file if you like.

### Chroot

At this point we will [chroot](https://wiki.archlinux.org/index.php/Chroot) into the new system.

```Shell
arch-chroot /mnt
```

**_From this point on, it is assumed you are inside the chroot, and file paths will be written accordingly!_**

### Timezone, Localization, and Network

See [Timezone](https://wiki.archlinux.org/index.php/Installation_guide#Time_zone), [Localization](https://wiki.archlinux.org/index.php/Installation_guide#Localization), and [Network](https://wiki.archlinux.org/index.php/Installation_guide#Network_configuration)

### Root Password

Don't forget to set your root password! Make sure it's a good one!
We won't cover creating any users here as it's not needed for a barebones bootable system. Technically the root password isn't either, but if you forget that leaves your system wide open.  
Just call `passwd` to set it, since you are already the root user.

### Enable tpm2-abrmd service

We installed and started this daemon on the live disk way back at the beginning of the guide. Enabling it now inside the chroot means systemd will automatically start it when we boot into our new system later.

```Shell
systemctl enable tpm2-abrmd
```

### Bootloader

For this system we are using `grub` because it has TPM support that we will need later and otherwise provides a nice menu to work with (if you don't need grub's menu then read up on `EFISTUB` as it could be a simpler and potentially more secure option). For now we will install grub manually, but later we will setup a pacman hook to do it automatically whenever it gets updated.

```Shell
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules=tpm
```

This installs grub in your efi partition, with the tpm module packaged into the core binary. It also creates an efi boot entry for "GRUB", which is also moved to the top of your boot order.

Edit `/etc/default/grub` to include the `tpm` module at the beginning of the `GRUB_PRELOAD_MODULES` setting then generate the config:

```Shell
grub-mkconfig -o /boot/grub/grub.cfg
```

This creates a grub config file that grub will read when it loads at boot. This includes your menu entries (ones for Arch are auto-generated). See [this page](https://wiki.archlinux.org/index.php/GRUB#Configuration) for details.

### Make the system bootable

In order to boot with an encrypted disk, we need to make sure there is a way to enter the passphrase at boot to unlock the disk. This will be securely automated over the following sections so that manual entry is not required, but for now we will setup a manual process so you don't get stuck unable to boot without a live disk.

To do this we can add a simple passphrase prompt to our early boot system with an initramfs hook called `encrypt`. Edit `/etc/mkinitcpio.conf` and add `encrypt` to HOOKS anywhere *after* `keyboard`.  
Eg: `HOOKS=(base udev autodetect keyboard modconf block filesystems encrypt fsck)`

Once you have done that, you'll also need to add a kernel command line argument to your grub configuration to tell `encrypt` where to find your encrypted disk, the documentation for which is found [here](https://wiki.archlinux.org/index.php/Dm-crypt/System_configuration#Boot_loader).  
Basically, you need to edit `/etc/default/grub` again, and add `cryptdevice=PARTUUID=some-uuid-here:cryptroot` to `GRUB_COMMANDLINE_LINUX_DEFAULT` where `some-uuid-here` is the UUID of your root partition (`/dev/sda5` in our example) as reported by `blkid` and `cryptroot` matches where you mounted the LUKS partition above. Make sure that you use the `PARTUUID` here.  
Once this is done, regenerate the config again as above in the last section.

Finally, regenerate your initramfs to include the `encrypt` hook that we added to the config. The easiest way to do this is to just re-install the kernel package, which will trigger the initramfs to regenerate in a pacman post transaction hook.

```Shell
pacman -S linux
```

Don't worry about what all this means for now. Initramfs and hooks will be covered in detail later! For now, you should make sure the system is bootable on it's own by shutting down, removing the live disk and attempting to boot. If it doesn't work, you'll need to review the steps above and troubleshoot. If you want to know more about the initramfs and hooks, check out the beginning portion of the "Automating Everything" section.

### Reboot into your new Arch installation

Before going any further, reboot into your new arch installation (in case you missed this in the last paragraph).

# Prepare a USB flash drive for TFA unlocking

As mentioned earlier, we will be using a USB flash drive as a second factor required to unlock the disk. This will be done by storing files needed to successfully retrieve the LUKS passphrase from the TPM on the drive, as well as half the key needed to authorize new policies. The files will be created in the next section and are useless without the specific TPM that created them so there is no harm storing them on an unencrypted partition. The amount of space required is so small it is recommended that you make a small FAT32 partition on the drive for this purpose and leave the rest for other uses (such as a LUKS encrypted partition for storing private keys). It could be as small as 32MiB, which is the minimum for FAT32 assuming 512 byte sectors (not that is has to be FAT32. If you use something like ext4 it will prevent windows from snooping around in the partition). For the purposes of this guide it will be assumed that this drive is mounted at `/mnt` for simplicity, but feel free to mount it wherever you like. The scripts we setup later will look for it by the partition UUID and mount it themselves to make sure it can always be found (as long as it is plugged in at the time).

# Mount a Ramfs as a working directory

Throughout the next couple section we will be generating a number of private keys and other sensitive data. It's a good idea to use a ramfs when generating keys, as data written to the disk is not necessarily wiped immediately (especially if you are using an SSD), leaving it open to data recovery. Maybe that's just being too paranoid. Up to you.
To mount a ramfs, do the following:

```Shell
mount -t ramfs -o 100m ramfs /path/to/your/chosen/mountpoint
```

You want to use ramfs rather than tmpfs because tmpfs can be swapped to the disk, while ramfs cannot. Further details on this are left to for you to research.  
**The following sections assume this ramfs as your shell working directory and will not be cleaning up sensitive files generated by various commands assuming that they will all get wiped when the ramfs is unmounted.**

# Sealing your LUKS Passphrase with TPM 2.0

In this section we will securely store a LUKS passphrase in the TPM so that we can use it later to automatically unlock our disk. The setup described here only has to happen once, and in the next section we will be automating the maintenance of everything.

*Please note that all file extensions used in this section with `tpm2_*` commands (eg. ***\*.policy***) are purely for readability. The tools do not expect any kind of extension.  
That said, any files that are saved for later use should retain their names as used here. The install and boot hooks we will be adding expect those files to have the names used here (though some can be configured to use alternate names without code changes via kernel command line arguments, as we'll see later).*

## Generate a primary key

A primary key is required to create any other type of key or TPM object. If those objects are stored outside the TPM the primary key is used to wrap or encrypt them. For our use case here we will be persisting all of the TPM objects that we need inside the TPM. Persisted objects are encrypted by the TPM internally such that the primary key is not required to use them, so we will not be persisting the primary key. That being said, we want to make our primary key unique so that it can't just be regenerated by someone else choosing the same options such as algorithm and key size (which form part of the primary key template). We will do this by setting an authorization value on the key when we create it. This value is included in the key derivation function input, making the key unique and also preventing it from being used without this value when it is loaded into the TPM. We will not persist our primary key as it is not needed after we create and persist the other TPM objects that we need, but it is recommended that you securely the store the authorization value in case you ever need to regenerate the primary key created here.

### Generate the authorization value

A simple way to generate this value is to just pull some random bytes from `/dev/random` with a tool like `dd`:

```Shell
dd if=/dev/random of=primary-key-authorization.bin bs=32 count=1
```

This will generate 32 random bytes and write them to a file.  
*Do not miss `count=1` or it will keep pulling 32 byte chunks of data from /dev/random continuously.*

### Generate the primary key with the authorization value

```Shell
tpm2_creatprimary --key-auth file:primary-key-authorization.bin --key-context primary-key.context
```

- `--key-auth file:primary-key-authorization.bin` passes in the authorization value that we just generated.
  - Note the `file:` prefix. This is needed whenever a key is specified in a file to a `tpm2_*` command. See [this manpage](https://github.com/tpm2-software/tpm2-tools/blob/master/man/common/authorizations.md).
- `--key-context primary-key.context` saves the key's context to a file for reference later.
  - Since we are using the `tpm2-abrmd` resource manager, our key is flushed from the TPM memory at the end of each command, but can be restored as needed using this file in subsequent commands (but only during this boot). If we were not using a resource manager but accessing the TPM directly the key would remain in the TPM's memory (which is quite limited) until explicitly flushed, or at power down.

There are many more options for this command, but in this case we are sticking to the defaults as they are plenty secure and the most compatible. They will be listed below without much additional detail (see [the manpage](https://github.com/tpm2-software/tpm2-tools/blob/master/man/tpm2_createprimary.1.md) for details).

- Hierarchy: Owner
- Algorithm: `rsa2048:null:aes128cfb`
  - Many TPMs won't offer much better than this as the spec doesn't require it. Depending on which version of the spec your TPM conforms to, it may also have `aes256` but it is recommended to use algorithms with matching key strengths (`rsa2048`'s 112 bits considered close enough to `aes128`'s 128 bits. `rsa3072`'s 128 bits would be a better match but most TPMs do not support it). `rsa16384` would be required for a 256 bit key strength to match `aes256`. You can check which algorithms your tpm supports using the [tpm2_testparms](https://github.com/tpm2-software/tpm2-tools/blob/master/man/tpm2_testparms.1.md) command.
- Hash Algorithm: `sha256`
- Attributes: `restricted|decrypt|fixedtpm|fixedparent|sensitivedataorigin|userwithauth|noda`
- Authorization Policy: null, which means it can never be satisfied.

## Add Authorization for Dictionary Attack Lockout

All Hierarchies have authorization values and/or policies that allow the generation of keys with their seeds, among other things, but these are typically not set for the Owner Hierarchy to allow it's use by multiple programs and users. If you lock it down, it is unlikely that bitlocker will be functional as it probably also uses the Owner Hierarchy (this was not tested, but is how the TPM specification expects the TPM to be used). The Endorsement Hierarchy is not used for this guide and will not be covered. The Platform Hierarchy's authorization is cleared on every boot, and it is expected that the BIOS or some other low-level firmware sets this early in the boot process, which means that the end user typically doesn't have access to the Platform Hierarchy.
In addition to the hierarchy authorizations, the TPM also has a Dictionary Attack (DA) Lockout mechanism that prevents dictionary attacks on the authorization values for primary keys and their children. Note that this mechanism does NOT protect hierarchy authorization values. The DA lockout also has an authorization value and/or policy that can be used to reset the lockout, as well as authorize a few other administrative commands, including the [tpm2_clear command](https://github.com/tpm2-software/tpm2-tools/blob/master/man/tpm2_clear.1.md), which will clear all objects from the TPM and reset the hierarchy seeds (meaning we would have to re-do everything in this section). This command can be run with either the Platform Hierarchy authorization (typically through a BIOS setup menu option) or the DA Lockout authorization. Since we have no control over the Platform Hierarchy, it is the DA Lockout authorization that we need to worry about. Setting an authorization value on the DA lockout should prevent `tpm2_clear` from being run by anyone else (such as windows), and should also prevent the lockout from being reset, both of which are important for security.  
*As of this writing it has not been verified if windows can somehow get around this and clear the tpm, but this should not be possible according to the spec unless it is able to communicate with the BIOS and use the platform authorization. Either way, setting this value is a good idea anyway and doesn't take long.*

### Generate the DA Lockout authorization value

This key should be stored securely, just as with the authorization value for the Primary key.

```Shell
dd if=/dev/random of=dictionary-attack-lockout-authorization.bin bs=32 count=1
```

### Set the DA Lockout authorization value

```Shell
tpm2_setprimarypolicy --hierarchy l --auth file:dictionary-attack-lockout-authorization.bin
```

- `--hierarchy l` identifies the DA Lockout "hierarchy" as the one to set the authorization on (that's a lowercase L, not a 1 or an I).
  - The Dictionary Attack Lockout isn't really a hierarchy, but it's authorization is set with the same command as the hierarchies.
- `--auth file:dictionary-attack-lockout-authorization.bin` sets the authorization value for the given "hierarchy".

It is also possible to set a policy, in addition to the authorization value, however this is not done here for simplicity. For any TPM object, the default authorization value is empty string, which allows anyone in, but the default policy is null, which can never be satisfied. Therefore it is critical to at least set the authorization value, but not necessarily the policy.

**WARNING**  
Do not loose this authorization value!!  
If you loose it, you will have no way to reset it aside from the Platform Hierarchy Authorization. This typically means going into your BIOS config and finding an option to reset the TPM, which will usually run a `tpm2_clear` with the Platform Authorization and erase everything in your TPM.

## Generate the new LUKS passphrase just for the TPM

Next we need to create a new LUKS passphrase to use with the TPM. If you set the iteration time on your previous passphrase to 10 seconds, this is where we will make sure your "normal" boot times are of a reasonable length by using a high entropy passphrase with the default 2 second iteration time (or you could even make it less than 2 seconds if you are confident enough in your randomly generated passphrase).  
Again we can use the `/dev/random` to generate a random key:

```Shell
dd if=/dev/random of=tpm-luks-passphrase.bin bs=32 count=1
```

And then we can use `cryptsetup` to add the key to the LUKS header:

```Shell
cryptsetup luksAddKey /dev/sda5 tpm-luks-passphrase.bin
```

- `luksAddKey` tells `cryptsetup` we want to add a new passphrase.
- `/dev/sda5` specifies our LUKS device.
- `tpm-luks-passphrase.bin` specifies the new passphrase we want to add.

This command will prompt you for your previous passphrase before adding the new key in keyslot 1 (A LUKS2 device can have up to 32 passphrases numbered starting with 0).

## Create a policy to seal the passphrase with

Before we seal this new passphrase into a TPM object under our primary key, we need to create a policy to seal it with, so that it can only be accessed if the policy is satisfied. Normally such a policy would involve the values of PCRs that are known to contain measurements of a trusted boot configuration (such as the new arch install we just created), however PCR values are inherently brittle. Whenever you update your bootloader, kernel, BIOS or other values that get measured, the PCR values will change. We would then have to re-seal the passphrase because an object's policy is immutable after it is created. To mitigate this issue, there is a special kind of policy that we can seal our passphrase with that is colloquially referred to as a "wildcard policy". This is a policy that can only be satisfied by another policy that has been signed by an authorization key (and that signed policy must also be satisfied however it requires). This second policy is passed in at the time the object with the wildcard policy is to be used (when our passphrase is to be unsealed and used to unlock the disk).  
In order to create a wildcard policy, we need an authorization key that will be used to sign the secondary policy that is used to satisfy it. This authorization key will be persisted in the TPM under our primary key so that it is never stored in the clear on the disk. The authorization key will only be able to sign new policies with an authorization value (similar to the primary key authorization). Half of the authorization value will be stored on our encrypted disk, and the other half on our USB drive. By doing this, the disk must already be unlocked *and* the external USB drive mounted in order to access the authorization key to sign a new policy.  
To be clear here, we aren't splitting the key itself into two parts, but the "password" needed to use the key that is stored only in the physical TPM on the machine in question. You need both the specific TPM *and* the full "password" to do anything with the key.

### Create an access value for the policy authorization key

*To better differentiate terminology, the authorization value for our policy authorization key will be referred to as an **access value** from here on.*

Similar to previously, the access value will be pulled from `/dev/random`

```Shell
dd if=/dev/random of=policy-authorization-access.bin bs=64 count=1
```
<!-- markdownlint-disable-next-line MD036 -->
*Note we doubled the number of bytes to 64 here, as we will be splitting this value in half, and we want to ensure it is just as difficult to guess half the value (assuming someone has obtained the other half somehow) as it was to guess the whole values that we generated before for things like the DA Lockout*

Next we will convert the access key to hexadecimal to make it more shell-safe, and split it into two parts:  
*(if a binary file is accidentally printed to the shell it could include non-printing characters that break some shells)*

```Shell
xxd -p -c 256 policy-authorization-access.bin > policy-authorization-access.hex

split -n 2 policy-authorization-access.hex policy-authorization-access
```

This will produce two files named `policy-authorization-accessaa` and `policy-authorization-accessab` that each contain 256bits of the 512bit access key in hexadecimal string format.  
Then we will copy half of the access key to a restricted folder in `/root` and make it read-only:

```Shell
mkdir /root/bootkeys

chmod 600 /root/bootkeys

cp policy-authorization-accessaa /root/bootkeys/policy-authorization-accessaa.hex

chmod 400 /root/bootkeys/policy-authorization-accessaa.hex
```

The file cannot be written to prevent accidental overwrite. The root user can explicitly change the permission if needed so this isn't an issue. The folder is not read-only so that we can add more files to it later.

The other half of the key will be copied to the special partition on the USB drive we setup earlier (assumed here to be presently mounted at `/mnt`):

```Shell
mkdir /mnt/$(cryptsetup luksUUID /dev/sda5)

cp policy-authorization-accessab /mnt/$(cryptsetup luksUUID /dev/sda5)/policy-authorization-accessab
```

The idea here is to create a directory on the USB drive to store the files for this computer so they are separated from similar files for another computer you might have. Later our scripts will be able to identify the correct directory by running a similar command to get the UUID of the luks container. If you only intend to use this USB drive with one computer you can just put things at the root of the partition as the scripts will fall back to this location if it can't find a folder named with the UUID.

### Create an authorization key for the policy

We will create this key in the TPM and restrict it's access with the key we just created:

```Shell
tpm2_create --parent-context primary-key.context --parent-auth file:primary-key-authorization.bin --key-auth hex:0x$(cat policy-authorization-accessaa policy-authorization-accessab) --key-algorithm rsa2048:rsapss-sha256:null --attributes "fixedtpm|fixedparent|sensitivedataorigin|userwithauth|sign" --key-context policy-authorization-key.context
```

- `--parent-context primary-key.context` encrypts the key under the primary key created previously.  
- `--parent-auth file:primary-key-authorization.bin` provides the primary key authorization value so that we can use it to encrypt the new key.
- `--key-auth hex:0x$(cat policy-authorization-accessaa policy-authorization-accessab)` sets the authorization value for the new key.
  - Since this value is now in hexadecimal, and split into two files, we need to concatenate the two files with a shell substitution and pass the result as a hex value by prefixing `hex:0x` to it. See [this manpage](https://github.com/tpm2-software/tpm2-tools/blob/master/man/common/authorizations.md) for details on passing auth values as hexadecimal.  
  *(Yes you could just use the original file right now, but this shows you how it will be done later)*  
- `--key-algorithm rsa2048:rsapss-sha256:null` sets the key algorithm.
  - This argument specifically sets it to be an `rsa2048` key with a signing scheme of `rsapss` (RSASSA-PSS) using `sha256` as the hash algorithm, as well as a null symmetric algorithm since this key can't be used for encryption anyway. See [this manpage](https://github.com/tpm2-software/tpm2-tools/blob/master/man/common/alg.md).  
- `--attributes fixedtpm|fixedparent|sensitivedataorigin|userwithauth|sign` sets the TPM object attributes for the key.
  - See [this manpage](https://github.com/tpm2-software/tpm2-tools/blob/master/man/common/obj-attrs.md) for details, and note that the attributes here restrict this key to only be a signing key, and to only be accessible with the auth-key value provided, among a few other things.  
- `--key-context policy-authorization-key.context` saves the key's context to a file for reference later.
  - just like with the primary key.

Unlike the primary key, most of the options that have defaults have been specified here in order to create this key just for signing our policies. The only option not specified is the hash algorithm, which is sha256 by default and is not to be confused with the hash algorithm specified as part of the signing scheme above. This is used for a different purpose.

#### If you get an error here

Some TPMs don't support all commands. If you get an error here about the `Esys_CreateLoaded` command not being supported you will have to remove the `--key-context` option from `tpm2_create`, and add:

```Shell
--public policy-authorization-key.public --private policy-authorization-key.private
```

These options save the public and private portions of the key (encrypted with your primary key) to files.

Then you will have to load the created key into the TPM memory with a separate command to get the `key-context`:

```Shell
tpm2_load --parent-context primary-key.context --public policy-authorization-key.public --private policy-authorization-key.private --key-context policy-authorization-key.context
```

The options given to this command are fairly self explanatory given what we have covered so far.

### Store the policy authorization key in the TPM permanently

We will be using the policy authorization key every time we unseal the disk (to verify the signature on the signed policy), so it is easiest to store it permanently in the TPM. To do this, we use the `tpm2_evictcontrol` tool. It is not clear why the tool is called that beyond the tool's name matching the internal TPM command's name. Possibly this is a reference to the TPM taking control of the object when you persist it, and "evicting" it from the NVRAM when you remove it (the same command does both).

```Shell
tpm2_evictcontrol --object-context policy-authorization-key.context --output policy-authorization-key.handle
```

- `--object-context policy-authorization-key.context` specifies the object that should be permanently stored in the TPM.
- `--output policy-authorization-key.handle` saves the internal handle (NVRAM address) where the object was stored to a file that can later be used to reference that object, like a context file except it works across boots.
  - *You can also use a raw NVRAM address in hex format (e.g. 0x8000004) but the handle file includes some other data that allows the TPM to verify that the key you are looking for is* ***actually*** *the one stored at the address specified.*

Since the key will be needed at boot before unlocking the disk, we copy the handle file to `/mnt/your-luks-container-uuid` (recall we are assuming your second factor USB flash drive is mounted at `/mnt`).

```Shell
cp policy-authorization-key.handle /mnt/your-luks-container-uuid/policy-authorization-key.handle
```

We will also copy a backup of the handle file to `/root/bootkeys` and restrict it's access as we did with the half of the access key.

```Shell
cp policy-authorization-key.handle /root/bootkeys/policy-authorization-key.handle

chmod 400 /root/bootkeys/policy-authorization-key.handle
```

Storing the handle file in the clear on the USB flash drive is not a security issue as it simply refers to the key's location in this TPM's NVRAM. It does *not* provide access to the private area of the key (and the public area is always available anyway, if you have access to the TPM it is in, through `tpm2_nvreadpublic` and `tpm2_readpublic`).

### Get the authorization key's name

The name of the authorization key (which is a digest that uniquely identifies the key in the TPM even if it is moved to a different NVRAM location) is needed to create the wildcard policy.

```Shell
tpm2_readpublic --object-context policy-authorization-key.handle --name policy-authorization-key.name
```

- `--object-context policy-authorization-key.handle` specifies the TPM object to read the public area of.
- `--name policy-authorization-key.name` saves the name portion of the public area to a file.

As with the handle, we will need this name at boot before unlocking the disk, so we copy it to the USB flash drive:

```Shell
cp policy-authorization-key.name /mnt/your-luks-container-uuid/policy-authorization-key.name
```

We will also copy a backup of the name file to `/root/bootkeys` and restrict it's access.

```Shell
cp policy-authorization-key.name /root/bootkeys/policy-authorization-key.name

chmod 400 /root/bootkeys/policy-authorization-key.name
```

### Create Wildcard Policy with the authorization key

Finally, we can create the wildcard policy! Start by opening a trial authorization session. A trial session is a session that can be used to create a policy for later use, but not to authorize access to anything.

```Shell
tpm2_startauthsession --hash-algorithm sha256 --session seal-wildcard-policy.session
```

- `--hash-algorithm sha256` specifies the hash algorithm to use for the session (all auth sessions are variations of HMAC sessions).
- `--session seal-wildcard-policy.session` specifies the file to save the session to so it can be used in subsequent commands.

This tool starts a trial session by default. `--policy-session` is required to start a real session.

Now create the policy:

```Shell
tpm2_policyauthorize --session seal-wildcard-policy.session --name policy-authorization-key.name --policy seal-wildcard-policy.policy
```

- `--session seal-wildcard-policy.session` specifies the trial session just created.
- `--name policy-authorization-key.name` specifies the name of the authorization key that will be used to sign policies that can satisfy this policy.
- `--policy seal-wildcard-policy.policy` saves the policy to a file so that it can be used during object creation later.

Finally, flush the trial session from TPM memory:

```Shell
tpm2_flushcontext seal-wildcard-policy.session
```

This last step is not really necessary because we will be rebooting very soon, but is good practice.

## Seal the LUKS passphrase with a persistent sealing object under the primary key

Now that we have made a policy, we can seal the LUKS passphrase we created into a persistent TPM object that is only accessible with that policy.

### Create a sealing object under the primary key

```Shell
tpm2_create --parent-context primary-key.context --parent-auth file:primary-key-authorization.bin --attributes fixedtpm|fixedparent|adminwithpolicy --sealing-input tpm-luks-passphrase.bin --policy seal-wildcard-policy.policy --key-context sealed-passphrase.context
```

This is almost identical to how the Policy Authorization Key was created, so only differences differences will be listed, along with some defaults that are being used:

- `--attributes fixedtpm|fixedparent|adminwithpolicy`
  - The final attribute here ensures the sealed object can only be unsealed with a policy.
- `--sealing-input tpm-luks-passphrase.bin` passes the previously created LUKS passphrase as the data to be sealed in the object.
- `--policy seal-wildcard-policy.policy` sets the policy of the sealed object to the wildcard policy created previously.
- Default Key Algorithm: `hmac` (sealed data can only be a keyed hash).
- Default Hash Algorithm: sha256

If you encountered an error with `tpm2_create` previously, repeat the same steps here to create the key and then load it into the TPM in a separate command.

### Store the sealing object in the TPM NV Storage

As with the Policy Authorization Key, this sealing object will be used at every boot, so we will store it permanently in the TPM. This process is basically identical to the above with the Policy Authorization Key so only the commands will be listed:

```Shell
tpm2_evictcontrol --object-context sealed-passphrase.context --output sealed-passphrase.handle

cp sealed-passphrase.handle /mnt/your-luks-container-uuid/sealed-passphrase.handle

cp sealed-passphrase.handle /root/bootkeys/sealed-passphrase.handle

chmod 400 /root/bootkeys/sealed-passphrase.handle
```

## Creating an authorized policy to unseal the LUKS passphrase on boot

At this point we have sealed the LUKS passphrase in a TPM object that is restricted with a policy that must be satisfied by another policy that is signed with a key. In order to satisfy this policy, we must create a second policy and sign it. The second policy will be created such that it is satisfied only if the values of certain PCRs are the same as when the policy was created. However, since we are about to make a bunch of changes to the boot process, the current values in the PCRs are not the ones that will be found on our final Arch system. There are a few that can be expected not to change in this case, such as PCR 0, which is the BIOS code, but creating a signed policy that is satisfied by only a few PCR values leaves our sealed LUKS passphrase vulnerable if anyone ever got ahold of that policy and the signature.

Since we will need this policy at boot to unseal the LUKS passphrase, we will store it on the USB flash drive, just as we did with the handles for the two objects we saved in the TPM. The policy file just contains a digest of each component of data that went into creating it (PCR values in this case) so storing it on the unencrypted flash drive is harmless so long as the policy requires a robust set of PCR values. In addition, it is useless unless paired with this specific TPM so storing them separately adds to the overall security. To use the policy the user (or the automated script we will be using later) must know the 'recipe' and re-create the policy digest inside a real authorization session by adding the values of the same that went into the original, after which the TPM will compare the two digests. The policy is satisfied if they match. Normally a policy is stored as part of the TPM object, however this one is stored in a file because it will be used to satisfy the wildcard policy that is stored in the TPM object. Since the policy is accompanied by a signature from the authorization key, nobody can tamper with it without causing the signature to fail verification. However if the policy is weak (such as by only requiring a couple PCR values), then there is no need for tampering since it will be easy to satisfy while making malicious changes to other parts of the boot configuration.

To mitigate this vulnerability while also maintaining convenience, we can create a temporary policy that will only work on the next boot, and never again afterward. This is possible because the TPM has an internal 32-bit counter that is incremented on every boot, never decremented, and can't be reset without running `tpm2_clear` which requires authorization and would also clear our sealed key from the TPM (see previous section about the Dictionary Attack Lockout Authorization). We can create a policy that includes a requirement that the value of the boot counter be exactly one plus the current value such that it can only be satisfied on the next boot (in addition to a couple PCR values that we do not expect to change under most circumstances, like PCR 0).

This strategy will also be used whenever we install an update for the kernel or the boot loader, though it will be done automatically in install hooks that we will setup later. Whenever we boot, a script (also to be setup later) will look first for a "more secure" policy that works, and failing that (such as when we install a kernel update), it will look for a temporary policy as described above. If this temporary policy is satisfied then it will automatically create a new "more secure" policy with the new PCR values that incorporate the updated kernel (once it unlocks the disk with the temporary policy and gains access to the second half of the policy authorization key's access value). We can take advantage of this automated policy creation in our initial setup too, by manually creating a temporary policy now and then letting the boot script automatically create the "more secure" policy when we reboot into our final arch system for the first time.

### Create a temporary policy

With all of the above said, lets create the temporary policy.  
Begin by starting a trial auth session, just like when creating the wildcard policy:

```Shell
tpm2_startauthsession --hash-algorithm sha256 --session temporary-authorized-policy.session
```

Add the PCR values that we know will not change to the policy:

```Shell
tpm2_policypcr --pcr-list sha256:0,1,2,3,7 --session temporary-authorized-policy.session
```

- `--pcr-list sha256:0,1,2,3,7` specifies the use of PCRs 0-3 and 7 from the sha256 bank.
  - Many TPMs support multiple banks of PCRs that use different algorithms. At minimum there is usually sha1 and sha256. To check what your TPM has allocated, run `tpm2_pcrread`.
  - If your TPM only has sha1, adjust this option accordingly. The boot script will use sha256 by default but an alternative can be specified on the kernel command line.
- `--session temporary-authorized-policy.session` specifies the trial session we just created.

Add the boot counter + 1 requirement using some `sed` magic to get the current boot counter:

```Shell
tpm2_policycountertimer --session temporary-authorized-policy.session --policy temporary-authorized-policy.policy --eq resets=$(($(tpm2_readclock | sed -En "s/[[:space:]]*reset_count: ([0-9]+)/\1/p") + 1))
```

- `--session temporary-authorized-policy.session` specifies the trial session we just created.
- `--policy temporary-authorized-policy.policy` specifies the file where the final policy should be saved.
- `--eq` specifies an equality comparison.
- `resets=<see above>` specifies that the comparison should be done with the restarts counter and the value it should be compared with.
  - Note that the `=` here has nothing to do with the type of comparison to be done, which just happens to be equality in this case.
  - The shell expansion is trimmed here for readability, but it basically uses `tpm2_readclock` to get the current `reset_count` and adds one. For example, if the current `reset_count` is 156, then this argument would boil down to `resets=157`

After creating the policy, we flush the session from the TPM memory:

```Shell
tpm2_flushcontext temporary-authorized-policy.session
```

### Sign the Policy

In order for the wildcard policy to accept this new policy, it must be signed by the key we created. To do this, we can use the `tpm2_sign` command:

```Shell
tpm2_sign --key-context policy-authorization-key.handle --auth hex:0x$(cat policy-authorization-accessaa policy-authorization-accessab) --hash-algorithm sha256 --scheme rsapss --signature temporary-authorized-policy.signature temporary-authorized-policy.policy
```

- `--key-context policy-authorization-key.handle` specifies the key that we want to sign with.
- `--auth hex:0x$(cat policy-authorization-accessaa policy-authorization-accessab)` specifies the authorization value needed to access the key, just as we did when we created it.
- `--hash-algorithm sha256` specifies the hash algorithm to be used for the message digest.
- `--scheme rsapss` specifies the signing scheme to use.
  - This tool is supposed to be able to auto-detect this from the key you are using but there appears to be a bug with that at the time of writing, so just specify it.
- `--signature temporary-authorized-policy.signature` specifies the file to save the signature in.
- `temporary-authorized-policy.policy` specifies the value to be signed.

### Copy the policy and its signature to the USB drive

We will need these files to unlock the drive at boot, so they are copied to the USB flash drive.

```Shell
cp temporary-authorized-policy.policy /mnt/your-luks-container-uuid/temporary-authorized-policy.policy

cp temporary-authorized-policy.signature /mnt/your-luks-container-uuid/temporary-authorized-policy.signature
```

There is no need to save these files elsewhere since they won't work again.

## Testing everything so far

Now that we have our second LUKS passphrase sealed into the TMP, we should test and make sure everything is working so far. To do this, we can make a simple policy to unseal the passphrase with. This policy will be like he temporary one above, except without the boot counter requirement, so please make sure it is **NOT** persisted anywhere as this could compromise the whole setup (the assumption is you are still working in the ramfs we have been using thus far and so it will be cleared when it is unmounted).

### Create and sign the test policy

All these commands have been covered above, so they will just be listed here:

```Shell
tpm2_startauthsession --hash-algorithm sha256 --session test-authorized-policy.session

tpm2_policypcr --pcr-list sha256:0,1,2,3,7 --session test-authorized-policy.session --policy test-authorized-policy.policy

tpm2_flushcontext test-authorized-policy.session

tpm2_sign --key-context policy-authorization-key.handle --auth file:policy-authorization-access.bin --hash-algorithm sha256 --scheme rsapss-sha256 --signature test-authorized-policy.signature test-authorized-policy.policy
```

### Verify the policy

Here we will use the policy we just created to unseal the passphrase we sealed into the TMP, and then have `cryptsetup` verify that it is a valid passphrase for our disk. First, we need to verify the signature we just created, and produce a validation ticket.

```Shell
tpm2_verifysignature --key-context policy_authorization_key.handle --hash-algorithm sha256 --message test-authorized-policy.policy --signature test-authorized-policy.signature --ticket test-authorized-policy.tkt
```

- `--key-context policy_authorization_key.handle` specifies the key in the TMP that was used to sign the message being verified.
- `--hash-algorithm sha256` specifies the hash algorithm used when signing. This *must* match what was used when tpm2_sign was called.
- `--message test-authorized-policy.policy` specifies the "message" or file that was signed.
- `--signature test-authorized-policy.signature` specifies the signature of the message that should be checked.
- `--ticket authorized-policy.tkt` specifies the file to output the verification ticket to.
  - This ticket is passed to subsequent commands to confirm the validity of the file being passed to them (in this case the policy).

### Create a real auth session

Next we need to create a ***real*** auth session that can be used for authentication with the TMP.

```Shell
tpm2_startauthsession --hash-algorithm sha256 --policy-session --session test-authorization.session
```

  `--policy-session` specifies that this session should be a *real* auth session that can be used for authentication with the TPM.  
  Other options here have already been covered above.

### Recreate the policy in the real auth session

Next we have to re-create the policy in this *real* session. This is how the TMP verifies policies — by comparing the policy hash in the *real* auth session with the one embedded in the TMP object (which in this case is the wildcard policy). With wildcard policies, `tpm2_policyauthorize` is used to compare the hash in the session with the one in the external policy file (that has been verified with `tpm2_verifysignature` to be signed with the key that the wildcard policy allows). If the verified external policy's hash matches the one in the session, the hash in the session is replaced with the hash of the wildcard policy, thus allowing this session to unseal our passphrase.

```Shell
tpm2_policypcr --pcr-list sha256:0,1,2,3,7 --session test-authorization.session

tpm2_policyauthorize --session test-authorization.session --input test-authorized-policy.policy --name policy-authorization-key.name --ticket test-authorized-policy.tkt
```

- `--input test-authorized-policy.policy` specifies the policy being verified.
- `--ticket test-authorized-policy.tkt` specifies the verification ticket produced above.

Other options have already been covered.

### Unseal and test the passphrase

Our auth session is now ready to unseal our passphrase (assuming you haven't encountered any errors so far). We do this with `tpm2_unseal`:

```Shell
tpm2_unseal --auth session:test-authorization.session --object-context sealed-passphrase.handle | cryptsetup open /dev/sda5 --test-passphrase && echo "success!"
```

- `--auth session:test-authorization.session` specifies the session that is used to authorize the unseal.
  - This could also be a key's auth value if it didn't use policy based authorization.
- `--object-context sealed-passphrase.handle` specifies the object to unseal.

The output of `tpm2_unseal` is printed to STDOUT by default, and we pipe this directly into cryptsetup, where we use the `--test-passphrase` option of the `open` action to check the passphrase without doing anything else. This test will simply return 0 (success) if the passphrase is good, so we echo some feedback if this is the case so we know it worked.

Hopefully this test went well for you. If not, you'll have to double check the documentation, re-read above, and troubleshoot. If you need to re-do the steps in this section you should probably use `tpm2_evictcontrol` to delete the objects we persisted to the TMP the first time around so you don't have stray objects stored.

# Securing the boot process

This section can be completed either using an Arch Linux live disk, or an already installed Arch Linux system. You are responsible for installing any needed packages (if you've been following from the beginning you already have everything), and for ensuring the security of your private keys (to be generated below).

## Taking Control of Secure Boot

Before getting into how to take control of secure boot, read at least the first two sections of [Rod's Guide to Controlling Secure Boot](http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html) before proceeding to get a better background on how secure boot works.  
Another excellent resource is [this guide from the Funtoo Wiki](https://www.funtoo.org/Secure_Boot), or [this archived page from the Gentoo Wiki](https://web.archive.org/web/20201005194738/https://wiki.gentoo.org/wiki/Sakaki's_EFI_Install_Guide/Configuring_Secure_Boot). A few more options are linked in the resources section (including one from the NSA!).  
All of these are similar to this section in that they will show you how to take control of secure boot (and in some cases how to secure grub, as covered in the next section). Feel free to use them instead of this one if they work for you. In particular, this guide only describes one pathway and set of tools to configure secure boot (though it is the pathway that will hopefully work in the most cases). If it doesn't work for your hardware/firmware, those guides have other variations that may work.  
If you do follow one of those guides instead, make sure to come back here for the remaining sections where we secure grub and set up some pacman hooks to automate the signing of our bootloader with the new secure book keys, among other important things.

### Generating New Secure Boot Keys

Assuming you are still here, the first step to take control of secure boot on your machine is to generate new secure boot keys of your own. In this guide we will also be retaining the default keys so you can still boot Windows and get firmware updates with secure boot on. If you have decided not to retain those keys it should be easy to skip the relevant sections below.  
To generate a new Platform Key (PK), Key Exchange Key (KEK), and Database Key (db), you can use `openssl`. The examples in this guide will be using `openssl 1.1.1`, which is the latest release at the time of writing (openssl 3.0 is not ready for primetime yet).

The following command will produce an RSA 2048 private key, and a matching public key certificate.

```Shell
openssl req -new -x509 -newkey rsa:2048 -keyout PK.key -out PK.crt -days 7300 -sha256 -nodes
```

- `req` is the `openssl` certificate request tool.
- `-new` tells `req` to create a new certificate request.
- `-x509` tells `req` to create a  self-signed certificate rather than just a request for one (which you would sent to a CA to get signed).
- `-newkey rsa:2048` tells openssl to generate a new private key using RSA 2048.
- `-keyout PK.key` specifies the output file for the private key.
- `-out PK.crt`  specifies the output file for the certificate.
- `-days 7300` specifies how long the certificate should be valid for.
  - Since we are putting this certificate in our computer firmware, we want it to last a while. Will you still have this computer in ~20 years?  
- `-sha256` specifies that sha256 should be used for the message digest.
- `-nodes` this tells openssl to not encrypt the private key.
  - If you want to encrypt it with a password, remove this option and you will be prompted, however `req` defaults to an encryption cipher that some consider to be too weak (3DES) and can't be configured otherwise. Alternatively you could use the `pkcs8` tool from `openssl` to encrypt the db key with better parameters after generating it, or see below for another option.

When you run this command you will be prompted to enter some details about yourself as the issuer of the certificate. You can put as little or as much as you want here, but at least set the common name and/or organization. These can also be set from the above command with, for example, `-subj /CN=your common name/O=your org name/` if you do not want to do it interactively.  
Unfortunately it is difficult to find a good list of all values that can go in here. They are listed in [RFC 5280 section 4.1.2.4](https://tools.ietf.org/html/rfc5280#section-4.1.2.4), but the short names are not included there. You can find some of them on [this SO post](https://stackoverflow.com/questions/6464129/certificate-subject-x-509).  
As an example, this is the subject/issuer you'll find in the default PK on a lenovo thinkpad from 2016: `/C=JP/ST=Kanagawa/L=Yokohama/O=Lenovo Ltd./CN=Lenovo Ltd. PK CA 2012`

#### Generate the keys

Run the above command three times, generating a PK, KEK, and db key.

```Shell
openssl req -new -x509 -newkey rsa:2048 -keyout PK.key -out PK.crt -days 3650 -nodes -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd PK/"

openssl req -new -x509 -newkey rsa:2048 -keyout KEK.key -out KEK.crt -days 3650 -nodes -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd KEK/"

openssl req -new -x509 -newkey rsa:2048 -keyout db.key -out db.crt -days 3650 -nodes -subj "/C=CA/ST=Alberta/L=Calgary/CN=My Name, yyyy-mm-dd db/"
```

Make sure you store the private keys (`.key`), as well as the original certificates in a safe place as with the other sensitive data we have created previously (again a LUKS encrypted flash drive partition could be a good choice). You will need the db key and certificate regularly to re-sign your bootloader, so we will also want to copy that one to `/root/bootkeys` like we did with certain files in the TPM section. Before that though, we should do more to protect the db key when the disk is unlocked than just using file system controls, this is a private key after all. Lets encrypt our db key more securely than `req` would have without `-nodes`.

### Generate a PGP key

Wait, a PGP key? What does that have to do with what we are doing here? While we could certainly securely encrypt our db key with the `openssl pkcs8` tool, we will be using a PGP key in the next section to secure grub. Using this same key to encrypt the db key saves you having to enter multiple passphrases to unlock keys when doing a system update, as `gpg-agent` will hold on to the passphrase for you for 10 minutes after you enter it (This is the default behaviour. To change this to a different amount of time add `default-cache-ttl some-number-of-seconds` to the config file below).  
As alluded to above, to create a PGP key we will use the package `gnupg` (Gnu Privacy Guard) which implements the OpenPGP standard. This package is already installed since it is a dependency of `pacman`. The two parts of this package we will be using are `gpg` which is the main command line tool, and `gpg-agent` which is a key generation and management daemon that `gpg` launches as needed and interfaces with. The version of the package used to make this guide was `2.2.21`.

#### Increase default `gpg-agent` KDF iterations

By default `gpg-agent` will calibrate it's key derivation function (the function that transforms your passphrase into a cryptographic key with an acceptable amount of entropy) so that it takes 100ms to unlock on your given system. This is similar to what LUKS does, except the default target for LUKS is 2 seconds to mitigate low entropy passphrases. We even increased this to 10 seconds for our backup LUKS passphrase!  
Recall the idea here is to make it more costly for an attacker to brute force the passphrase. If your passphrase is really really good then the point is moot, but "high entropy" and "easy for a human to remember" rarely go hand in hand. Ultimately it's up to you.  
To increase `gpg-agent`'s iteration time we can create a config file for it in `/root/bootkeys/.gnupg/gpg-agent.conf` with an alternate iteration target. You are welcome to use whatever value you want. Here we will match the LUKS default of 2 seconds (2000ms).

```Shell
mkdir /root/bootkeys/.gnupg

printf '%s\n' 's2k-calibration 2000' > /root/bootkeys/.gnupg/gpg-agent.conf
```

The config file is at this path as we will be using this as our home directory for `gpg`. Since this key is just for securing grub and the db key on this machine it makes sense to keep it separate from any other keys you use personally (which would end up in `/home/youruser/.gnupg` by default). We will be including an option in all our `gpg` commands to ensure that the home directory is `/root/bootkeys/.gnupg`. If you are experienced with `gpg` and would rather manage this key with the rest of your keys then by all means adjust the following commands and scripts accordingly.

#### Generate a new PGP keyring and key

The following command will generate a new keyring in `/root/bootkeys/.gnupg` containing the new key. `gnupg` will automatically prompt you to create a passphrase to secure the keyring. You will be asked for this passphrase whenever you need to use the key to sign files. This will happen when you update your system with pacman and the scripts we will setup in the following sections are triggered, so requiring you to enter your passphrase at this point is just one more prompt in the already manual system update process.

```Shell
gpg --homedir /root/bootkeys/.gnupg --gen-key
```

- `--homedir /root/bootkeys/.gnupg` specifies the directory that gpg should look for a keyring and config files in.
  - If no keyring is found here it will make one.
  - We are using a non-standard home directory here to prevent clashing with other uses of `gpg`. If you know what you are doing you are welcome to put the key in an existing keyring, however you will have to adjust the scripts in the next section to specify which key they should be using rather than just taking the first key it finds (which is the only key in this case here).
- `--gen-key` specifies that gpg should generate a new key using the default settings (RSA 2048 key pair).
  - This will prompt you to create a new user profile to store the key under (name and email). These do not have to be real unless you plan to share the public portion of this key with others (probably better to make a different key for that).

There are other ways to generate a key, this just appeared to be the simplest. This [Article](https://www.redhat.com/sysadmin/creating-gpg-keypairs) from RedHat describes the process in more detail.

#### Increase key expiry date

This key we will be using solely to secure our boot process, so like our secure boot certificates we want it to last a while without having to think about extending it's expiry date. By default it will expire after only a year or two. To increase this we have to use the `gpg --edit-key` interactive prompt. Below this interaction is reproduced for reference with some parts trimmed for brevity.

```Shell
gpg --homedir /root/bootkeys/.gnupg --edit-key <the email address you entered when creating the key>
# Trimmed a bunch of output about the gpg version and a list of all the keys in the trustdb
gpg> expire
Changing expiration time for the primary key.
# Trimmed instructions for how to enter the value
Key is valid for? (0) 7300
Key expires at <date ~20 years from today>
Is this correct? (y/N) y
# You will be prompted for your passphrase here, after which the list of keys will be printed again showing the new date on the primary key
gpg> key 1
# The list of keys will be printed again with a * next to the selected subkey
gpg> expire
Changing expiration time for a subkey.
# Trimmed the same process as above except it probably won't ask for your passphrase again since it is within 10 minutes.
gpg> save
# Saves changes and exits
```

At this point both the primary key and the subkey should be set to expire in 20 years similar to our secure boot certificates. You are welcome to choose a different amount of time, or make it never expire if you want.

#### Encrypt the db key

With all of that done, we can finally encrypt our db key and copy it and the db certificate to `/root/bootkeys`

```Shell
gpg --homedir /root/bootkeys/.gnupg --recipient <the email address of your new PGP key> --output /root/bootkeys/db.key --encrypt db.key
```

- `--homedir /root/bootkeys/.gnupg` specifies the directory that gpg should look for a keyring and config files in.
- `--recipient <the email address of your new PGP key>` specifies the recipient of the encrypted file (us), meaning that our new key should be the one used to encrypt the file.
  - Since this is asymmetric encryption, the public key is used to encrypt the file, and then the private key will be used to decrypt it later.
  - If you had another person's public key in your keyring you could encrypt a file for them instead. You can also add multiple recipients and all of them would be able to decrypt the same file. Not that any of that is relevant here.
- `--output /root/bootkeys/db.key` specifies the output file, which we might as well write directly to `/root/bootkeys`.
- `--encrypt db.key` actually tells gpg to encrypt the file. This option MUST be last for some reason.

Finally, copy the certificate to `/root/bootkeys` and restrict access to both files:

```Shell
cp db.crt /root/bootkeys/db.crt

chmod 400 /root/bootkeys/db.key
chmod 400 /root/bootkeys/db.crt
```

Now we can continue with our secure boot setup. Well use this PGP key again when we secure grub in the next section.

### Converting the certificates to EFI signature list format

The certificates generated by `openssl` are not in the format needed by the tools we will use to install them in the firmware. To fix this we will use some utilities from the `efitools` package. The version we are using here is `1.9.2`.  
We want to convert our certificates to EFI Signature List (`.esl`) format. To do this, the following command is used:

```Shell
cert-to-efi-sig-list -g <your guid> PK.crt PK.esl
```

- `-g <your guid>` is used to provide a GUID to identify the owner of the certificate (you). If this is not provided, an all zero GUID will be used.
- `PK.crt` is the input certificate.
- `PK.esl` is the output esl file.

#### Generate a GUID

In order to provide our own GUID for the certificate owner, we have to generate one. There is a multitude of ways to do this, but in this case a utility called `uuidgen` will do the trick:

```Shell
GUID=$(uuidgen)
echo $GUID > /root/bootkeys/GUID.txt
```

The first line generates the GUID and assigns it to a shell variable called GUID that we will use below, the second line echos the value into a text file so we can keep it beyond the current shell session.

#### Convert the certificates

Run the above command to convert each of the three certificates, also adding the GUID we just generated:

```Shell
cert-to-efi-sig-list -g $GUID PK.crt PK.esl

cert-to-efi-sig-list -g $GUID KEK.crt KEK.esl

cert-to-efi-sig-list -g $GUID db.crt db.esl
```

### Preserving the default KEK and db, and dbx entries

Since we want to be able to dual boot Windows 10, it is important that we preserve the default KEK, db, and dbx entries from Microsoft and the computer manufacturer. Maintaining Microsoft's keys will ensure that Windows can still boot, and maintaining the manufacturer keys will ensure we can still install things like EFI/BIOS updates, which are often distributed as EFI binaries signed by the manufacturer's key, that run on reboot to update the firmware. It is especially important that we preserve the dbx entries if we are keeping the Microsoft keys, as the dbx contains a black list of signed efi binaries (mostly all signed by Microsoft) that are not allowed to run, despite being signed by an certificate in the db (one of the Microsoft keys). "But I only need the db and dbx keys for this" you might be thinking. True, but if we do not keep the KEKs too, you cannot benefit from updates to the db and dbx issued by Microsoft or your computer manufacturer. Removing the manufacturer's PK does prevent them from issuing new KEKs, but this is much less likely, and if you want to take control of secure boot there is no way around replacing the PK, unless you have access to the private key it was made with.  
Finally, while most firmware has an option to restore factory default keys, if yours does not, you may want to keep these keys for that use case too.

To preserve the existing keys, we will use another utility from `efitools` called `efi-readvar`. This utility runs in Linux user-space and can read efi secure variables such as the secure boot variables:

```Shell
efi-readvar -v PK -o original_PK.esl
```

- `-v PK` specifies the efi variable to read
- `-o original_PK.esl` file to output the contents to (notice this is also in `.esl` format.)

#### Copy Original Keys

Run the above command for each of PK, KEK, db, and dbx

```Shell
efi-readvar -v PK -o original_PK.esl

efi-readvar -v KEK -o original_KEK.esl

efi-readvar -v db -o original_db.esl

efi-readvar -v dbx -o original_dbx.esl
```

#### Append original keys to new keys

With the `.esl` file format, we can easily merge our new keys with the existing ones by simply concatenating the files:

```Shell
cat KEK.esl original_KEK.esl > all_KEK.esl

cat db.esl original_db.esl > all_db.esl
```

### Signing the EFI signature list files

While we don't technically need to do this step, since the firmware should accept any keys in secure boot setup mode (we'll get to that later), it is more correct to use signed update files and some firmware might insist on it.  
If you want to add a KEK or db entry after secure boot is no longer in setup mode, you'll have to sign it with the next highest key so let's do that now as practice. The PK is considered the root of trust, just like the root certificate from a certificate authority such as entrust or lets encrypt. The following command is used to sign the signature lists:

```Shell
sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth
```

- `-k PK.key` specifies the private key for the certificate.
- `-c PK.crt` specifies the certificate to sign with.
- `PK` is the EFI variable the output is intended for.
- `PK.esl` is the EFI signature list file to sign.
- `PK.auth` is the name of signed EFI signature list file, with a `.auth` extension indicating that it has an authentication header added.

#### Sign the files

Run the above command for each `.esl` file:

```Shell
sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth

sign-efi-sig-list -k PK.key -c PK.crt all_KEK KEK.esl all_KEK.auth

sign-efi-sig-list -k KEK.key -c KEK.crt db all_db.esl all_db.auth

sign-efi-sig-list -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth
```

The PK signs itself, the PK also signs the KEKs, and our KEK (the only one we have the private key for) signs the db and dbx keys. Note that since we don't have anything to add to the dbx, we just sign the original list.  
Our db key is later used to sign EFI binaries that we want to boot, the KEK is used if we want to add new db entries, and the PK is used if we want to add new KEK entries.

### Installing the new Secure Boot Keys

The first step here is to put secure boot into setup mode by removing the current PK. This can be done from the BIOS setup utility, but beyond that, the exact steps differ greatly across hardware. Typically there will be a security section, and in that, a secure boot section. This is where you would have turned secure boot off in order to install Arch Linux initially or to boot the live disk. Look for an option to put secure boot into setup mode, or an option to delete all secure boot keys. *If you see both, delete all keys*, as this often prevents certain issues with the tool we will be using (we saved all the old keys and will be replacing them anyway). Some firmware may require a firmware password to be set before these options are shown. Setup mode is on when there is no PK. Once a new PK is set, secure boot turns back to user mode, and any updates to any of the secure variables must by signed by the next highest key.
> Quick note: you may see a reference to `noPK.esl` or similar in Rod's guide and the Gentoo wiki archive (both linked at the start of this section). This is an empty file signed with the PK that can be used to "update" the PK to nothing (remove the PK) while in user mode, thereby putting secure boot back into setup mode without entering the BIOS setup utility. This works because the PK can be updated in user mode as long as the update is signed by the current PK. Unless you are changing your keys often, you likely won't need this.

Once secure boot is in setup mode, we can use an `efitools` utility called `efi-updatevar` to replace each of the secure variables:

```Shell
efi-updatevar -f PK.auth PK
```

- `-f PK.auth` specifies the file to update the variable with. `PK.auth` is the efi signature list (signed in this example) that will be set on the variable.
  - If you wan to use a .esl file here, you need to also add a `-e` before or after this.
- `PK` is the secure variable we want to update

*NOTE:* This command as written will **replace** all the values in the variable. It is possible to instead append with `-a` but this seems to have problems on some firmware, while just replacing everything usually works, and in this case we added the old keys to ours and (ideally) cleared out all the secure variables before starting anyway. The reason it is ideal to clear out all the variables before starting is also because some firmware will not accept a replacement if there is a value present. Clearing all the keys and using the replacement command above appears to work in the most cases.

#### Install new secure boot keys

Run the above command for dbx, db, KEK, and PK, preferably in that order, but just make sure the PK is last so that we keep setup mode active.

```Shell
efi-updatevar -f dbx.auth dbx

efi-updatevar -f all_db.auth db

efi-updatevar -f all_KEK.auth KEK

efi-updatevar -f PK.auth PK
```

Since we signed our efi signature lists and created auth files we should theoretically be able to update the KEK, db, and dbx even after setting the PK (which takes us out of setup mode), but `efi-updatevar` seems to have trouble doing this at least on the machine used as a testbed for this guide. There are other tools that work better for updating with signed esl files (`.auth`) when secure boot is in user mode. For example `KeyTool`, also from `efitools` seems to work fairly well, however it is an efi binary so you have to reboot to use it (like your BIOS setup), which is more cumbersome.

### Test your new secure boot keys

If you successfully completed all of the above sections, you now have your own keys added to secure boot, so you can start signing bootloaders and other efi binaries with your db key!  
If you want to quickly test your handiwork `efitools` supplies a `HelloWorld` efi binary that you can sign and try to boot into. Assuming your efi system partition is mounted at `/efi` as we setup earlier, we can use a tool called `sbsign` from the `sbsigntools` package to sign the efi binary like so:

```Shell
mv /efi/EFI/Boot/bootx64.efi /efi/EFI/Boot/bootx64-prev.efi # Rename the existing default boot entry so that we can restore it later.

sbsign --key db.key --cert db.crt --output /efi/EFI/Boot/bootx64.efi /usr/share/efitools/efi/HelloWorld.efi
```

- `--key db.key` specifies the private key to sign the file with.
- `--cert db.cry` specifies the public certificate for the given private key that was added to secure boot.
- `--output /boot/EFI/Boot/bootx64.efi` specifies where to save the signed version of the file.
- `/usr/share/efitools/efi/HelloWorld.efi` specifies the file to sign.

After running this, reboot, and enter BIOS setup. Enable secure boot and move your boot drive to the top of your boot order (above grub). When you exit setup it should try to boot the HelloWorld binary since it is in the efi default location for that drive, and because we signed it, it should work. If it doesn't, then something went wrong up above.  
To get back to linux, just put grub back at the top of your boot order.  
**Don't forget to replace the hello world binary with the file that used to be there!**

***WARNING!!***  
BEFORE you reboot, if you haven't already make sure you save the original private keys, as well as the TPM auth values somewhere secure! Assuming you have been following closely, all your keys are sitting in your current working directory which is a ramfs and all data will be LOST PERMANENTLY when you reboot, requiring you to repeat some of the steps above to make new keys.

## Securing the BIOS

**Important!**

Now that we have setup secure boot, we need to make sure unauthorized users cannot just turn it off. To do this, set an administrator password on your BIOS configuration. Every BIOS is a little different so the specifics can't be covered here, but if you don't do this, you will remove nearly all benefit of using secure boot!

## Securing grub

Now that we have added our own secure boot key we can use it to sign our grub binary in order to ensure with reasonable confidence that it has not been tampered with (the actual signing will be done in the next section). In addition to grub itself, we also want to have reasonable confidence that the other files loaded by grub have not been tampered with, such as the grub configuration file and the kernel and initramfs image that will contain our boot scripts. We can do this by configuring grub to only load files that are signed with a trusted key. The documentation for this can be found [here](https://www.gnu.org/software/grub/manual/grub/grub.html#Using-digital-signatures), but essentially we need to embed the public portion of our PGP key into the grub binary, and then sign any files that grub will be loading with the private portion. We also need to secure advanced grub functions with a passphrase to prevent the signature checking function from just being turned off.

### Export the public portion of the PGP key

If you skipped over the Secure Boot section, we generated a new PGP key there:
[Generate a PGP key](#generate-a-pgp-key)

Now that we have a PGP key, we need to tell grub to only load files that have been signed by it. To do this, we embed the public part of the key into the grub binary. Before this can happen, we have to export the public portion to a file.

```Shell
gpg --homedir /root/bootkeys/.gnupg --output /root/bootkeys/secure-grub.pgp --armor --export <yourChosenUser@exampleDomain.com>
```

- `--armor` adds ASCII armor to the exported key file (makes it shell safe by converting the binary file to ASCII text).
- `--export <yourChosenUser@exampleDomain.com>` specifies which key should be exported based on the email address entered when the key was generated.

This is just a public key, but still might as well restrict access to it.

```Shell
chmod 400 /root/bootkeys/secure-grub.pgp
```

### Configure grub to use the key

To embed the key in the grub binary, we can add the `--pubkey` flag to grub-install. We will be automating this in the next section, but here is how you would do it manually, using the same settings we used earlier when installing Linux.

```Shell
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules=tpm --pubkey /root/bootkeys/secure-grub.pgp
```

**Warning!**  
Embedding the key will automatically turn on grub's `check_signatures` rule, and you will not be able to boot unless all files grub loads are signed (or you drop into the grub shell and disable the rule). It is recommended that you don't shutdown and reboot without having completed the next two sections at least.

### Configure grub with a passphrase

Even with an embedded public key and `check_signatures` turned on, anyone with physical access can just enter the grub shell and turn it off. To prevent this, we need to lock those features behind a passphrase. Grub provides a way to do this with pbkdf2 hash derivation such that it can be included in `grub.cfg` without exposing the password to anyone reading the file. Password generation is done with a utility included with grub called `grub-mkpasswd-pbkdf2`, which will prompt you to enter your chosen passphrase twice and then print out the resulting salt and hash.

```Shell
grub-mkpasswd-pbkdf2 --iteration-count 2300000 > password-hash.txt
```

- `--iteration-count 2300000` specifies that 2300000 pdkdf2 iterations should be used which will result in a ~2 second unlock time on the test computer.
  - This number was obtained by running `cryptsetup benchmark` and looking at the number of iterations per second for PBKDF2-sha512, which is what this utility uses by default. This number should adjusted to suit your target system. 2 seconds was chosen to match the LUKS default, which was chosen to balance security and convenience. You could also make this larger, as the password is not likely to be needed very often.
- `> password-hash.txt` specifies that the output of `grub-mkpasswd-pbkdf2` should be written to a file.

For more information on `grub-mkpasswd-pbkdf2`, including additional configuration options, see [this page](https://www.gnu.org/software/grub/manual/grub/grub.html#Invoking-grub_002dmkpasswd_002dpbkdf2).  
From here you can edit the file to just contain the hash (remove the text preceding `grub.pbkdf2...`), and then use `cat` to append it to an appropriately prepared `40_custom` as per below. This is much easier than transcribing it twice (assuming you are using a tty prompt. If you installed a desktop environment already then you can just copy and paste).

With the passphrase hash generated, grub needs to be configured to accept it. The simplest way to accomplish this is to add the following lines to `/etc/grub.d/40_custom`

```Text
set superusers="root"
password_pbkdf2 root grub.pbkdf2.sha512.2300000.some-sha512-hash.some-other-sha512-hash
```

The second line here should include the real output of your call to `grub-mkpasswd-pbkdf2`. This will setup a single "superuser" called "root" with the password you just entered. For more details, see [this page](https://www.gnu.org/software/grub/manual/grub/grub.html#Authentication-and-authorisation).
> *Note the Arch Linux grub package is specifically configured to NOT overwrite 40_custom when updating grub, unlike the 10_linux file in the same directory, which is overwritten (as you will see below).*

### Signing files for grub

Once we embed the public key in the grub image, all files loaded by grub must be signed with the key we generated. Signatures are expected in separate signature files with the same name as the signed file. For a relatively simple grub setup like we have here, the files we need to sign are:

- `/boot/grub/*`
- `/boot/vmlinuz-linux`
- `/boot/initramfs-*`

This includes our grub config file (`grub.cfg`), all grub modules not already included in the grub binary, the kernel image itself (`vmlinuz-linux`), and any initramfs images we have (there should be two, a regular one and a fallback).

To sign all these files, we can use `find` with the `-exec` option:

```Shell
find /boot -type f \( -path "/boot/grub/*" -or -name "vmlinuz*" -or -name "initramfs*" \) -not -name "*.sig" -exec gpg --homedir /root/bootkeys/.gnupg --detach-sign --yes {} \;
```

`find`:

- `/boot` specifies the starting directory for the search.
- `-type f` specifies that only files should be returned (not directories, links, etc).
- `\(` an escaped `(` used tell `find` to group clauses together. It must be escaped or bash will try to interpret it as something else.
- `-path "/boot/grub/*"` specifies files in `/boot/grub` should returned.
- `-or -name "vmlinuz*"` specifies files starting with `vmlinuz` should be returned.
- `-or -name "initramfs*"` specifies files starting with `initramfs` should be returned.
- `\)` an escaped `)` to close the grouping started above.
- `-not -name "*.sig"` specifies files ending in `.sig` should NOT be returned.
  - This ensures that if we run this more than once it overwrites the signature files rather than signing them as well (e.g. `filename.sig.sig`)
  - Since we have grouped all the preceding clauses, this will apply to all of them.
- `-exec gpg --homedir /root/bootkeys/.gnupg --detach-sign --yes {} \;` tells `find` to execute this command on every result. Details below.

`gpg`:

- `--homedir /root/bootkeys/.gnupg` specifies our non-standard home directory.
- `--detach-sign` specifies that gpg should put the signature in a separate file.
- `--yes` specifies that gpg should assume "yes" for most questions.
  - This saves you from having to answer 100 "signature already exists, do you want to replace it?" questions when running this more than once.
- `{}` will be replaced with a the current `find` result, and tell gpg to sign that file as it loops over all the results.
- `\;` an escaped `;` tells `find` that this is the end of the exec command.

You will be prompted for your gpg keyring passphrase once, after which it will be saved by `gpg-agent` for about 10 minutes by default. This command might take a couple of minutes to complete depending on how fast your CPU is, as there are quite a few files in the grub directory to sign. When running this multiple times we are simply overwriting all of the signatures with new ones as we don't know which files may have been changed by an update, and checking each one before re-signing would take significantly longer for no real benefit.

# Automating Everything

Why do yourself what the computer can do for you?

## Automating Early Boot Tasks with Initramfs

You can perform custom actions at early boot by adding scripts to something called the initramfs. [This wiki page](https://en.wikipedia.org/wiki/Initial_ramdisk) explains what that is really well.  
The two sentence version as quoted from the `mkinitcpio` man page is:  
> The initial ramdisk is in essence a very small environment (early userspace) which loads various kernel modules and sets up necessary things before handing over control to `init`. This makes it possible to have, for example, encrypted root file systems and root file systems on a software RAID array.

`init` is process 1 on most modern linux systems. It is the first process run by the kernel and all other processes are spawned from it and it remains running until shutdown. In the case of Arch Linux, init is usually `systemd`. For more info, check out the [Arch Boot Process](https://wiki.archlinux.org/index.php/Arch_boot_process).

### Arch Linux and mkinitcpio

As of this writing, Arch Linux uses a set of shell scripts in a package called `mkinitcpio` to generate initramfs images. There is talk among the Arch maintainers of switching to a package called `dracut` that is more widely used in other distributions (`mkinitcpio` is custom made for Arch Linux), but so far this has not happened. `mkinitcpio` provides a mechanism to add custom scripts, or "hooks" to the initramfs to customize the boot process. It is these hooks that we will use to automatically unseal our LUKS passphrase from the TPM at boot. Further documentation on `mkinitcpio` can be found in it's [Arch Wiki Page](https://wiki.archlinux.org/index.php/Mkinitcpio), although that page is sadly not quite representative of the generally excellent quality of articles on the Arch Wiki. While there is plenty of very useful information in there, it falls just short of actually explaining how to create custom hooks or presets. The [man page](https://jlk.fjfi.cvut.cz/arch/manpages/man/mkinitcpio.8) gives a bit more detail on some parts, but also stops short of showing an example of it all coming together.

The default `mkinitcpio` config file is located at `/etc/mkinitcpio.conf`. There are also "preset" files located in `/etc/mkinitcpio.d/` that are generated for each kernel package you have installed based on the template found at `/usr/share/mkinitcpio/hook.preset`. With all that said, the defaults will be fine for the purposes of this guide. The `linux` preset (generated from the above template for the `linux` package) uses the default config file to generate a main initramfs image, and a fallback image in case there is a problem with the first one. These images are nearly identical except for the file name and a few options, and updating the default config will change both of them. The format of the presets actually allow the use of different config files for different initramfs images if desired (you can even generate more than two images), but that is not necessary here.

For our purposes here, we wil be adding two custom hooks. One to automatically unseal our LUKS passphrase with the TPM called `tpm2_encrypt`, and another to help us boot Windows in a Bitlocker friendly way called `bitlocker_windows_boot`. You will find these custom hooks in a folder in this repo called `/mkinitcpio`. There are two files related to each hook that you will find there in folders called `hooks` and `install`. This is because `mkinitcpio` hooks come in two parts, the build/install hook, and the runtime hook(s).

#### Install Hook

The install hook tells `mkinitcpio` what to include in the initramfs so that the runtime hook can function. For example, `tpm2_encrypt` needs access to a number of `tpm2-tools` binaries, as well as other tpm related libraries and kernel modules. The install hook also contains a help text that can be printed by `mkinitcpio` using the `--hookhelp hookname` flag once the hook is installed. In general `mkinitcpio` can automatically detect shared libraries needed by the binaries included by the install script, but if you look at `tpm2_encrypt` you will see that some additional ones had to be added manually.

#### Runtime Hook

The runtime hook can define up to four different shell functions that are run at four different points in the boot process. These are listed [here](https://wiki.archlinux.org/index.php/Mkinitcpio#Runtime_hooks). The functions themselves can do whatever you want them to, within the bounds of the early boot environment. A list of common hooks available in Arch Linux through various packages can be found on the same page linked just a little further down.

***Important***  
As noted in the [Arch Wiki](https://wiki.archlinux.org/title/Mkinitcpio#Runtime_hooks) for `mkinitcpio`, runtime hooks only work with busybox init (presently the default for Arch Linux). If you use the systemd hook to init with systemd then you will not be able to use the runtime hooks created for this guide. ("init" here means initial setup, not process 1 as described earlier).

### Adding the hooks to the initramfs

To "install" these custom hooks on your system, simply copy them to `/etc/initcpio/install/` or `/etc/initcpio/hooks/` as appropriate and ensure they have the executable flag (`chmod +x`). You still have to add these hooks to `mkinitcpio.conf` in order to add them to the initramfs image, which we will do below after explaining how they work a little more.

#### tpm2_encrypt

For `tpm2_encrypt` there are comments throughout the runtime hook file (or otherwise very descriptive names), as well as an extensive helptext in its install file, so how it works will not be explained in great detail here.  
To summarize, it looks for the files that we copied to our flash drive earlier and uses them to build a real authorization session and unseal the LUKS passphrase that we previously sealed in the TPM. It has a lot of checks for input errors (kernel arguments), and will offer to create a new authorized policy (after you have entered your passphrase manually) if something fails. It will even show you which PCR values changed if it fails to unseal the passphrase so you can make an informed decision about whether you expected those changes before entering your passphrase manually. If you have a temporary authorized policy like we created earlier, it will create a new "more secure" authorized policy without asking (assuming it is able to unseal the passphrase with that temporary policy).  
Please look at the source to learn more. In particular, do not neglect to read the help text in the install hook, as it contains critical information regarding kernel command line arguments needed for it to work.

To add `tpm2_encrypt` to your initramfs image, simply edit `mkinitcpio.conf` to include it in `HOOKS`. Please note that as mentioned in the help text for `tpm2_encrypt`, it is written as an extension for the `encrypt` hook that was added earlier (if you followed the installation section), and should be placed *before* `encrypt` in `HOOKS`.  
Here is an example: `HOOKS="base udev autodetect keyboard modconf block filesystems tpm2_encrypt encrypt fsck"`  
Hooks are run in the order listed in the config file for each of the four parts of the boot process (Eg. All early hooks are run in this order, then all main hooks, etc).

#### bitlocker_windows_boot

This hook needs a little more explanation as to why it is needed, although the actual implementation is extremely straightforward and again will not be discussed in detail. Just look at the hook file, it's only a couple lines.

The typical way to dual boot Windows and linux with GRUB is to chain-load the windows boot loader from GRUB. The problem with this approach is that if you are using TPM based bitlocker on Windows and you update GRUB the PCR measurements for GRUB would change, which would break bitlocker.  
To get around this we can add another hook to our initramfs that will set the EFI boot-next\* variable to the Windows boot entry and then reboot before fully initializing Linux. This way, Windows always boots the same way - directly from the Windows boot manager, without even needing to know that GRUB exists. If Windows wants to update it's own boot manager, it already has a process for re-sealing the Bitlocker key in the TPM (similar in result to the process we are setting up for linux involving the temporary authorized policies, but probably implemented completely differently).  
*\* EFI boot-next overrides the boot order you set in your BIOS but only for the next boot*

There doesn't appear to be a way to set the boot-next variable directly in GRUB. If you know how, please let me know or submit a PR! This would save us having to load the linux kernel just to set the boot-next variable.

Add `bitlocker_windows_boot` the same way you added the first hook. Edit `/etc/mkinitcpio.conf` and add `bitlocker_windows_boot` to `HOOKS`. You'll want to add it near the front of the list so it runs before the other hooks (faster), but make sure that it's at least after `base`. The hook will only be activated if it sees a certain kernel argument so it can live alongside our other hooks in the same initramfs image without having an effect on the boot process for linux.  

### Update the initramfs image with the new hooks

Now that the hooks have been added to the correct folders, and the config file, we need to generate a new initramfs image that includes these hooks.  
To do this, simply run

```Shell
mkinitcpio -p linux
```

- `-p linux` specifies the "linux" preset.
  - This preset was generated from the template when the `linux` package (the default kernel package in Arch Linux) was installed. If you are using a different kernel or preset, adjust accordingly.

### Update GRUB to include necessary kernel command line arguments

If you read the help text for `tpm2_encrypt` and/or the requirements for the `encrypt` hook then you know there are a few required command line arguments for these two hooks to work correctly. These arguments need to be added to our GRUB menu entries so they are passed to the kernel at boot. To do this, we need to update `/etc/default/grub` to include these arguments in `GRUB_CMDLINE_LINUX_DEFAULT`. The exact arguments needed are left for you to determine using the documentation provided, however here are example arguments:  
`tpm_files_part=PARTUUID=some-uuid-for-dev-sda5 cryptdevice=PARTUUID=the-uuid-of-the-luks-partition:cryptroot`  
There are many more optional arguments for `tpm2_encrypt` that are meant to provide flexibility without having to change the code in the hook, but we are sticking to the defaults here.
This is also in addition to any other kernel arguments you may want to add that are actually related to the kernel, such as the log level or the quiet flag.

*You will notice that we did not add any arguments to activate `bitlocker_windows_boot`, and we are also not re-generating the grub config with `grub-mkconfig` just yet. Both of these things are coming in the next section!*

## Automating Update and Install tasks with Pacman Hooks

Whenever we update our kernel or boot loader (or even just the bootloader config), the PCR measurements for those components will change. This means that any policy we have created that relies on the previous values will no longer work. To get around this, we can create a temporary policy (as discussed in detail above) that excludes those PCR values for a single boot cycle. This, along with some other useful tasks, can be done automatically with pacman transaction hooks so that we don't even have to think about it.

### Pacman hooks

Pacman hooks, also known as [alpm-hooks](https://www.archlinux.org/pacman/alpm-hooks.5.html), are a super easy way to automate parts of package management that would otherwise have to be done manually. Sometimes the Arch Linux developers install hooks with a package, such as with `mkinitcpio`, where the hook automatically re-generates your initramfs images after updating either the kernel or any of the mkinitcpio hooks you have installed via pacman.

Further reading about hooks is mostly left to you (everything you need to know is in the above manpage), however it should be noted that it appears that the default pacman hooks directory is `/etc/pacman.d/hooks` *not* the `/usr/local/etc/pacman.d/hooks` directory mentioned on the man page. This directory is where custom hooks should go. Hooks installed by packages should go in the system hooks directory `/usr/share/libalpm/hooks/` (also not exactly the one mentioned in the man page). If you want to see how that `mkinitcpio` hook mentioned above works, look for it here.

### Install the hooks

In this repo you will find a folder called `/alpm-hooks/`, which contains a number of hooks and supporting scripts written for this guide.

Three hooks are related to `grub` and secure boot, another creates a temporary policy for `tpm2_encrypt`.

To "install" these hooks simply copy them to `/etc/pacman.d/hooks` or `/etc/pacman.d/scripts` as appropriate (you may have to create these folders), and ensure they all have the executable flag (`chmod +x`). They will automatically be called whenever you update or install packages with pacman and the events that trigger them occur.
*The next few sections explain these hooks in more detail*

### GRUB updates

Updating the `grub` package does not trigger a re-install of the GRUB boot image on your efi partition, nor does it regenerate the configuration. This was probably a very conscious choice on the part of the Arch Linux maintainers. Everyone has their own slightly different setup, be it different partition scheme, or a non-standard install location, and auto-installing grub for everyone would probably cause more problems that it solves. That said, what is the point of updating the package if the image we are booting with isn't getting updated? Plus, who wants to remember to run `grub-install` and `grub-mkconfig` every time with the right arguments? Not to mention signing all the files with our PGP key. Lets add some hooks to fix this!

The main hook is called `grub-secure-setup.hook`. It runs a script with the same name which has four simple commands.

First it calls `grub-install` with the same arguments that we used earlier when we first installed it. If your installation is different, you'll want to edit the script accordingly.

The Second call needs a little more explanation. It calls `patch` and adds a few lines to `/etc/grub.d/10_linux` based on a patch file found in the same scripts folder. The script expects the patch file to be called `grub-10_linux-mod.patch`, and depending on wether you are dual-booting windows or not, you'll want to copy the corresponding patch file to `/etc/pacman.d/scripts` with that name.  
`grub_10_linux_with_windows_entry.patch` adds a GRUB menu entry that will boot our initramfs with the "magic" kernel argument that will activate the initramfs hook `bitlocker-windows-boot`. To do this manually, you could modify `/etc/grub.d/10_linux` and add a "linux" menu entry called "Windows 10" to your grub menu. Why do it this way rather than putting it in `/etc/grub.d/40_custom` where it probably belongs? Well this boot entry is based on the same initramfs image that grub automatically finds and creates entries for in `10_linux` and it's nice to take advantage of all that logic. There's only one problem: `10_linux` is overwritten every time the `grub` package is installed. This is why we need to re-patch `/etc/grub.d/10_linux` to include the Windows entry whenever `grub` is updated.  
So why not just duplicate `10_linux` and give it a different name like `11_windows` to add this entry? Then there would be an entire custom script to maintain that duplicates a lot of logic. By patching the existing file we can take advantage of any updates from the arch maintainers, since the patch only adds one line that calls a function defined earlier in the file. It is unlikely that it will change so drastically in the near future so that the patch no longer works. If it does, you can probably come back and find an updated one here.  
`grub_10_linux_without_windows.patch` is similar to the other patch file but excludes the Windows 10 entry. This patch is important to allow selecting the main linux boot entry without entering the GRUB root password that we added earlier by adding the `--unrestricted` flag to the menu entry.

Third, `grub-secure-setup` calls `grub-mkconfig` the same way we did earlier. Again, edit this script if your system is different.

Finally, it signs all the grub files with `find -exec` like we did above.

### Signing kernel and initramfs

Above we signed the kernel and initramfs in the same command as all the grub files. Here we have separated signing these two files into a separate hook called `grub-secure-sign-kernel-initramfs.hook` so that updating one of them doesn't have to trigger setting up grub again, when those files haven't changed. This hook does not have an accompanying script file as it only requires one command, which is simply included in the hook itself.

### Secure boot signing

Now that we have setup our own secure boot keys, we need to use the db key to sign our GRUB image (we already signed the kernel and initramfs, which will be verified separately by GRUB). Without this step, we do not have a complete chain of trust.

The hook is called `secure-boot-sign-grub`, which has an accompanying script of the same name in the `scripts` folder. The implementation is quite straightforward with plenty of comments, so just go read it yourself.

### tpm2-encrypt-create-temporary-policy

To automatically create a temporary policy when updating the kernel or bootloader, there is a hook called `tpm2-encrypt-create-temporary-policy`. This hook also has an accompanying script in the scripts folder. Similar to the `tpm2_encrypt` hook for `mkinitcpio` we will not be going into great detail on how it works here. The main parts were covered when we manually created a temporary policy in the previous part of this guide, and there are also comments throughout the script portion of the hook.  
The main thing to point out here is that this hook has two trigger sections, meaning it can be triggered by more than one event. In this case, it is triggered by an update to either the kernel or to GRUB, both of which already trigger other hooks to update their binaries in the efi partition (it will not run twice if both events occur).

### Trigger the hooks

With all the hooks "installed", re-install `grub` with pacman (`pacman -S grub`) to trigger the hooks related to grub and update the grub config with all the kernel arguments we added (to the main config file), as well as add the Windows boot entry and the other things discussed above. This will also trigger the hook to re-create the temporary policy we made earlier, but it was still good to go through that to better understand how this all works. We should not need to re-sign the kernel and initramfs as these have not changed.

# Conclusion

You're done! You made it to the end!
From here these scripts should mostly maintain things for you. All you have to do is make sure the USB drive is plugged in whenever you boot, and whenever you run `pacman -Syu` or equivalent.

# Resources

This section reproduces most of the links that were included in-line throughout the guide (it omits some sub-pages), as well as added some other useful links such as online manpages for tools used. All of these form the basis for the information contained within this guide, listed in no particular order, but organized by general topic area.

## Security Fundamentals

1. <https://en.wikipedia.org/wiki/Evil_maid_attack>
2. <https://en.wikipedia.org/wiki/Threat_model>
3. <https://xkcd.com/538/>
4. <https://en.wikipedia.org/wiki/Hardware_random_number_generator>

## TPM

1. <https://link.springer.com/book/10.1007%2F978-1-4302-6584-9>
2. <https://en.wikipedia.org/wiki/Trusted_Platform_Module>
3. <https://trustedcomputinggroup.org/resource/pc-client-specific-platform-firmware-profile-specification>
4. <https://trustedcomputinggroup.org/resource/pc-client-platform-tpm-profile-ptp-specification>
5. <https://trustedcomputinggroup.org/resource/tpm-library-specification>
6. <https://www.gnu.org/software/grub/manual/grub/grub.html#Measured-Boot>
7. <https://tpm2-software.github.io/>
8. <https://github.com/tpm2-software/tpm2-tools/tree/master/man>
9. <https://medium.com/@pawitp/full-disk-encryption-on-arch-linux-backed-by-tpm-2-0-c0892cab9704>
10. <https://blog.dowhile0.org/2017/10/18/automatic-luks-volumes-unlocking-using-a-tpm2-chip/>
11. <https://threat.tevora.com/secure-boot-tpm-2/>

## Arch Installation

1. <https://wiki.archlinux.org/index.php/Installation_guide>
2. <https://www.archlinux.org/mirrorlist/>
3. <https://wiki.archlinux.org/index.php/EFI_system_partition#Alternative_mount_points>
4. <https://wiki.archlinux.org/index.php/Chroot>
5. <https://wiki.archlinux.org/index.php/GRUB#Configuration>

## Linux Boot Process

1. <https://en.wikipedia.org/wiki/Initial_ramdisk>
2. <https://wiki.archlinux.org/index.php/Arch_boot_process>
3. <https://wiki.archlinux.org/index.php/Mkinitcpio>
4. <https://jlk.fjfi.cvut.cz/arch/manpages/man/mkinitcpio.8>
5. <https://wiki.archlinux.org/index.php/Dm-crypt/System_configuration#Boot_loader>

## Pacman Hooks

1. <https://www.archlinux.org/pacman/alpm-hooks.5.html>

## Drive Encryption

1. <https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LUKS_on_a_partition>
2. <https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#2-setup>
3. <https://manpages.debian.org/unstable/cryptsetup-bin/index.html>
4. <https://gitlab.com/cryptsetup/cryptsetup>
5. <https://wiki.archlinux.org/index.php/Dm-crypt>

## Secure Boot

1. <http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html>
2. <https://web.archive.org/web/20201005194738/https://wiki.gentoo.org/wiki/Sakaki's_EFI_Install_Guide/Configuring_Secure_Boot>
3. <https://www.funtoo.org/Secure_Boot>
4. <https://www.openssl.org/docs/man1.1.1/man1/openssl-req.html>
5. <https://tools.ietf.org/html/rfc5280#section-4.1.2.4>
6. <https://stackoverflow.com/questions/6464129/certificate-subject-x-509>
7. <https://manpages.debian.org/unstable/efitools/index.html>
8. <https://wiki.archlinux.org/index.php/Secure_Boot>
9. <https://askubuntu.com/questions/951040/how-shim-verifies-binaries-in-secure-boot>
10. <https://ubs_csse.gitlab.io/secu_os/tutorials/linux_secure_boot.html>
11. <https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd>
12. <https://media.defense.gov/2020/Sep/15/2002497594/-1/-1/0/CTR-UEFI-Secure-Boot-Customization-UOO168873-20.PDF> (Yes this is the NSA)

## Secure Grub

Some of the secure boot links above also cover secure grub but they are not included here to avoid duplication.

1. <https://gnupg.org/documentation/manuals/gnupg/Invoking-GPG.html#Invoking-GPG>
2. <https://www.gnu.org/software/grub/manual/grub/grub.html#Using-digital-signatures>
