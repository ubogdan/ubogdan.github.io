---
title: "Enable Password Reset Feature on Exchange 2013"
description: ""
date: "2022-03-23T19:54:45+02:00"
thumbnail: ""
categories:
- "Windows"
tags:
- "exchange"
widgets:
- "categories"
- "taglist"
---

Exchange Control Panel (ECP) is a web based management and configuration interface that allows you to manage various aspects of the server configuration. 
The password reset feature enables administrators to reset mailbox passwords over ECP.  

![Missing password reset](/images/exchange-no-password-reset.png 'Missing password reset')

<!--more--> 

At first glance, it doesn't seem like much, but it gives administrators the power to reset users' passwords securely, even when traveling.

To enable the Password Reset Feature, you need to open the Exchange Management Shell. and run the following commands
```shell
Add-PSSnapin Microsoft*

Install-CannedRbacRoles

Install-CannedRbacRoleAssignments

New-ManagementRoleAssignment -SecurityGroup "Organization Management" -Role "Reset Password"
```

No error is expected to be returned 
![Reset Password Powershell Output](/images/exchange-powershell-reset-password.png 'Reset Password Powershell Output')

Log out and log in back into ECP and you will be able to see the reset 

![Reset Password ECP](/images/exchange-password-reset.png 'Reset Password ECP')


