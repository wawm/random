######################################################################
# Version 1.0
# Linux add user to Multiple DC for Redhat 7
# wanazlan85@gmail.com
# This script will setup SSSD and Join Active Directory domain to Linux(Redhat 7)
# Example is to add for servers in 5 different datacenters
######################################################################

#!/usr/bin/python

import os
import time
import sys

if not os.geteuid() == 0:
    sys.exit("Only User Root Can Run This Script!")

#Making sure that Subscription manager is valid before proceeding
def checkpackages():

    chk_submgr = os.popen("subscription-manager list | grep Subscribed | awk '{print $2}'").read()

    if chk_submgr.strip() == "Subscribed":
        chk_pkg = os.popen("rpm -qa | grep -E 'sssd-client|realmd|oddjob|adcli|policycoreutils-python'").read()

        if not chk_pkg:
            reqpkg_cmd = os.popen("yum -y install sssd realmd oddjob oddjob-mkhomedir adcli policycoreutils-python >/dev/null 2>&1").read()
            print("Installing necessary packages")
            time.sleep(3)
            print(reqpkg_cmd)
        else:
            print("Package is installed! Checking Domain Status")
    else:
        print("Please check subscription manager status, Manual steps needed.")
        exit()

def joindomain():
    DC1_cmd = "echo <DomainPassword> | realm join -U svc_joinonly HS3-DOM-02.qhs.local"
    DC2_cmd = "echo <DomainPassword> | realm join -U svc_joinonly HS1-DOM-02.qhs.local"
    DC3_cmd = "echo <DomainPassword> | realm join -U svc_joinonly HS2-DOM-01.qhs.local"
    DC4_cmd = "echo <DomainPassword> | realm join -U svc_joinonly HS5-DOM-01.qhs.local"
    DC5_cmd = "echo <DomainPassword> | realm join -U svc_domainjoin HS0-DOM-02.qhstest.local"
    chk_srv = os.popen('uname -n | cut -f 1 -d-').read()
    chk_ad = os.popen('realm list | grep -i domain-name').read()

    if chk_srv.strip() == "S1":
        print("Server is DC1")
        os.system(DC1_cmd)
        print("Domain Joined!")
        print(chk_ad)
    elif chk_srv.strip() == "S2":
        print("Server is DC2")
        os.system(DC2_cmd)
        print("Domain Joined!")
        print(chk_ad)
    elif chk_srv.strip() == "S3":
        print("Server is DC3")
        os.system(DC3_cmd)
        print("Domain Joined!")
        print(chk_ad)
    elif chk_srv.strip() == "S4":
        print("Server is DC4")
        os.system(DC4_cmd)
        print("Domain Joined!")
        print(chk_ad)
    elif chk_srv.strip() == "S5":
        print("Server is DC5")
        os.system(DC5_cmd)
        print("Domain Joined!")
        print(chk_ad)
    else:
        print("Server is invalid, exiting")
        exit()
def regsssd():

    sed_sssd1 = "sed -i 's/%u@%d/%u/g' /etc/sssd/sssd.conf"
    sed_sssd2 = "sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf"
    sssd_restart = "systemctl restart sssd && systemctl daemon-reload"
    test_aduser = "id ad_testuser"
    add_sudo = os.popen('echo \'\"%COMMON ACTIVE DIRECTORY GROUP\" ALL=(ALL) NOPASSWD: ALL\' >> /etc/sudoers').read()

    print("Tweaking configuration for final step")
    time.sleep(5)
    os.system(sed_sssd1)
    os.system(sed_sssd2)
    os.system(sssd_restart)
    print("Testing AD User")
    os.system(test_aduser)
    print("Adding common group to Sudoers")
    os.system(add_sudo)

#Run functions
checkpackages()
joindomain()
regsssd()
