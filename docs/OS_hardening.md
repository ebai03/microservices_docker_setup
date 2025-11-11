# Operating System Hardening (Server)

## Security profile configuration  

The CIS Benchmark 2.0 for Redhat Enterprise Linux 9 will be used as a reference point to implement the relevant configurations for hardening the Operating System of the virtual machine. Each Benchmark represents a series of security recommendations created by a community of IT professionals with the aim of hardening organizations against cyberattacks (_CIS Benchmarks_, n.d.).

The benchmarks from CIS align with popular frameworks such as the NIST Cybersecurity Framework, HIPAA, PCI-DSS, and the ISO 27000 family (Dharap, n.d.)

To implement the security profile, the following steps will be taken:

- Root user: It is advisable to use it only as a last resort when necessary; some tools behave unexpectedly if we only use sudo.

Be careful with how sudo is used:  
- sudo -i ≈ log in as root (similar to su -). (Most recommended option)  
- sudo command runs only that command as root.  
- sudo -i starts an interactive shell as root.  

Apply the principle of least privilege (PoLP) is a security concept that states that a user, application, or system should only have access to the resources and permissions it needs to perform its specific task, and nothing more. In other words, the lowest possible level of access is granted to minimize risk in case of a security breach. 

### Password policies
Due to the access and control that root and administrator accounts have, it is necessary to establish policies to regulate and maintain an acceptable level of protection for each one. Within the benchmark document, section 5.3.3.1 "Configure pam_faillock module" is relevant, where regulations can be found regarding the maximum number of failed authentication attempts, minimum password length, and other considerations for a password to be "strong".



### Profile deployment
To configure the selected security profile, OpenSCAP will be used, a tool that allows analyzing the current configuration and searching for possible vulnerabilities within the system.

First, we need to install the necessary packages:
```sh
yum install openscap-scanner scap-security-guide
```

Next, we can use the info command to examine the contents of the file that contains the profiles we can use
```sh
oscap info /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml
```

This is the output of the command:

![oscap_info](./imgs/OS_hardening/image1.png)

In this case, the profile with the id ``xccdf_org.ssgproject.content_profile_cis_server_l1`` is the one we will use. To apply the scan and simultaneously generate a file with the scripts necessary to apply the rules:

```sh
oscap xccdf generate fix --profile xccdf_org.ssgproject.content_profile_cis_server_l1 /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml > remediate.sh
```

We can see the contents of the generated script with `vi`:

![remediate_sh](./imgs/OS_hardening/image2.png)

The old permissions must be changed (with chmod) so that it can be executed, after this it is possible that some account is deactivated for having an insecure password, if access to the system is completely lost the system must be rescued.

```sh
chmod +x remediate.sh
```

### Losing access to the system

It is possible that when we run the script with the fixes, the passwords of the active accounts on the machine expire, this happens

#### System Recovery
In case the configurations were applied with openscap and access to the system is accidentally lost (disabled accounts).
This is part of section *5.4.1.1 Ensure password expiration is configured (Automated)* where a maximum time for a password is configured after which it is disabled.

The purpose is **to prevent an attacker from accessing with compromised credentials**, it is recommended to set this period to 365 days or less, with the consideration that very repetitive changes may result in users using predictable or sequential passwords.

The lockout occurs because, when setting a password in the initial system setup, the `last change date field` is not set and any value of the `PASS_MAX_DAYS` parameter will cause the password to expire immediately. One possible solution is to fill the field with a command like:
```sh
chage -d "$(date +%Y-%m-%d)" root
```

However, for the purposes of the project, this function will be disabled. This can be done by excluding the rule from the script when generating it, or manually changing the parameter from the auto-generated script:

```SH
###############################################################################
# BEGIN fix (59 / 278) for 'xccdf_org.ssgproject.content_rule_accounts_maximum_age_login_defs'
###############################################################################

(>&2 echo "Remediating rule 59/278: 'xccdf_org.ssgproject.content_rule_accounts_maximum_age_login_defs'"); (

# Remediation is applicable only in certain platforms
if rpm --quiet -q shadow-utils; then
var_accounts_maximum_age_login_defs='-1' # <- FIJAR A -1

...

###############################################################################
# BEGIN fix (60 / 278) for 'xccdf_org.ssgproject.content_rule_accounts_password_set_max_life_existing'
###############################################################################

(>&2 echo "Remediating rule 60/278: 'xccdf_org.ssgproject.content_rule_accounts_password_set_max_life_existing'"); (
var_accounts_maximum_age_login_defs='-1' # <- FIJAR A -1
```

Once in the GRUB menu (where the boot options are listed), select the system entry and press ``e`` to edit it. It will look something like this:

```sh
setparams 'Rocky Linux (5.14.0-427.13.1.el9_4.x86_64) 9.6 (Blue Onyx)'

load_video
set gfx_payload=keep
insmod gzio
insmod part_msdos
insmod xfs
set root='hd0,msdos1'
if [ x$feature_platform_search_hint = xy ]; then
  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,msdos1 12345678-abcd-1234-5678-123456789abc
else
  search --no-floppy --fs-uuid --set=root 12345678-abcd-1234-5678-123456789abc
fi
linux /vmlinuz-5.14.0-427.13.1.el9_4.x86_64 root=/dev/mapper/rl-root ro crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M resume=/dev/mapper/rl-swap rd.lvm.lv=rl/root rd.lvm.lv=rl/swap rhgb quiet
initrd /initramfs-5.14.0-427.13.1.el9_4.x86_64.img
```

Go to the line that starts with ``linux`` and edit it to include the following at the end

```sh
systemd.unit=emergency.target

# Opciones alternas:
# systemd.unit=rescue.target
# Iniciar directamente en consola
# init=/bin/bash
```

Press Ctrl+X to boot with these changes or press F10 (the changes will be temporary)

Once the system has started, log in as root and execute the following in the console:

```sh
# Remontar root dir en modo rw
mount -o remount,rw /

# Reiniciar contraseñas
passwd root

# Reiniciar
reboot
```

Finally, restore the passwords with `passwd <user>` and reboot the system.

### Verificación de despliegue
Para verificar que se aplicaron correctamente los cambios, se puede volver a ejecutar la herramienta de openscap y guardar el resultado del análisis en un documento, en este caso los resultados serán guardados en html para una visualización más sencilla pero también se pueden guardar en un documento xml y visualizarlos localmente con vi.

```sh
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_cis_workstation_l1 --report cr.html /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml
```
Utilizando un cliente de scp se puede compartir el archivo por medio de ssh si conocemos la ip de la vm, esto lo podemos obtener con ip addr, posteriormente podemos abrir el archivo en un navegador.