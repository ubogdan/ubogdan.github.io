---
title: "Signing GIT commits with GPG"
description: ""
date: "2022-03-13T18:32:54+02:00"
thumbnail: ""
categories:
- "Programming"
tags:
- "programming"
- "git"
- "gpg"
widgets:
- "categories"
- "taglist"
---


Even if you don’t know about signed Git commits, you might have seen this on GitHub:
![Verified commit](/images/github-verified-commit.png 'Verified')

<!--more--> 

Making a commit “verified”, or to be more precise, signed, is not as hard as you might think.

Generate GPG Identity
---------------------
1. Open an terminal and paste the following command: `gpg --default-new-key-algo rsa4096 --gen-key`. 
```shell
$ gpg --default-new-key-algo rsa4096 --gen-key
gpg (GnuPG) 2.2.19; Copyright (C) 2019 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

GnuPG needs to construct a user ID to identify your key.

Real name: 
```
2. Enter the name you want to be associated with this key. We will use `John Doe` as example value.

```shell
$ gpg --default-new-key-algo rsa4096 --gen-key
gpg (GnuPG) 2.2.19; Copyright (C) 2019 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

GnuPG needs to construct a user ID to identify your key.

Real name: John Doe
Email address: 
```
3. Enter the email address , it must match the primary email address of your github.com or gitlab.com user. For this example we will use `john.doe@example.com`.

```shell
$ gpg --default-new-key-algo rsa4096 --gen-key
gpg (GnuPG) 2.2.19; Copyright (C) 2019 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

GnuPG needs to construct a user ID to identify your key.

Real name: John Doe
Email address: john.doe@example.com
You selected this USER-ID:
    "John Doe <john.doe@example.com>"

Change (N)ame, (E)mail, or (O)kay/(Q)uit? 
```
4. Normally you need to type `O` and hit the `Enter` key, but if you spellchecked the username or email address , this is the time to correct them. 

```shell
$ gpg --default-new-key-algo rsa4096 --gen-key
gpg (GnuPG) 2.2.19; Copyright (C) 2019 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

GnuPG needs to construct a user ID to identify your key.

Real name: John Doe
Email address: john.doe@example.com
You selected this USER-ID:
    "John Doe <john.doe@example.com>"

Change (N)ame, (E)mail, or (O)kay/(Q)uit? O
We need to generate a lot of random bytes. It is a good idea to perform
some other action (type on the keyboard, move the mouse, utilize the
disks) during the prime generation; this gives the random number
generator a better chance to gain enough entropy.
```

5. Enter strong password to protect the private key for this identity
```shell
$ gpg --default-new-key-algo rsa4096 --gen-key
gpg (GnuPG) 2.2.19; Copyright (C) 2019 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

GnuPG needs to construct a user ID to identify your key.

Real name: John Doe
Email address: john.doe@example.com
You selected this USER-ID:
    "John Doe <john.doe@example.com>"

Change (N)ame, (E)mail, or (O)kay/(Q)uit? O
We need to generate a lot of random bytes. It is a good idea to perform
some other action (type on the keyboard, move the mouse, utilize the
disks) during the prime generation; this gives the random number
generator a better chance to gain enough entropy.
gpg: key 274BCEB5173B46CD marked as ultimately trusted
gpg: revocation certificate stored as '/home/user/.gnupg/openpgp-revocs.d/0CDA98C19E1619C94275DDFC274BCEB5173B46CD.rev'
public and secret key created and signed.

Note that this key cannot be used for encryption.  You may want to use
the command "--edit-key" to generate a subkey for this purpose.
pub   rsa4096 2022-03-13 [SC] [expires: 2024-03-12]
      0CDA98C19E1619C94275DDFC274BCEB5173B46CD
uid                      John Doe <john.doe@example.com>
```

Export the GPG Identity
-----------------------
1. List gpg identities
```shell
$ gpg --list-secret-keys --keyid-format=long
home/user/.gnupg/pubring.kbx
-------------------------------
sec   rsa4096/274BCEB5173B46CD 2022-03-13 [SC] [expires: 2024-03-12]
      0CDA98C19E1619C94275DDFC274BCEB5173B46CD
uid                 [ultimate] John Doe <john.doe@example.com>

```
2. Export the public GPG key by ID.In our example `274BCEB5173B46CD` is the key id.
```shell
$ gpg --armor --export 274BCEB5173B46CD
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGIuG8cBEAC9og9e+dsRjKGT30d2/Knv89j81mJw4M6lC4MPBB2g1JcfBz08
rbGkk7hfhYR/wV+UjLUDDxFIeAZyp6Le7vwMZfBBteFlSN7VWO8c9st7wK3DYer7
rcroGmevSCRLJE+hPITTfHWJJLzYnIekQpvvGr7cnDNB3fXGO+yIfW6WrmrbgwR8
gg4bWNm57rJarxUD0ENjIBAorFWh+PvyNEY4on105BmcH339Yl6xiU/L2vJrMuX8
4qpiid9m+kHG0CRt6jTx25+NU/Tg8lMM6i0/C2CZRmtGwX6b6CjIetE9thCXCgvh
BPPfjnzMKTg2Vg6xTt0g1iQCx0z1UnRJa36Rh183VsFl/UIrsa3TORpBKXgiJDjh
x7gBf2SuPp2o7RQrsNtVISXEg+ygwH6YFnAxQSEODS5hbYkBnM2Gu31Tq7EwpBmX
YUmPLRqa8s6/R0cXDvJmV02KKzL60Y+BjCjd+8HxdFgpGI2ByxDbVixXX5gAyU6O
d+PuZ6+g8EHhx/asZTDUyzR8A2C2i+1mNHhvDC3/rR0bYB784BRxez2/SE9ZHEUs
oNu/mdq3QyvZ4cA221fsnBruuEXvgo+6CHmOiCMIaFGlyZSn3LbGBla9esIJcj8/
vD/PRGjkLqbT31mNHtPlQirzJO9SwFcXYneMCuOlL7flUu14ML22cO/b1wARAQAB
tB9Kb2huIERvZSA8am9obi5kb2VAZXhhbXBsZS5jb20+iQJUBBMBCAA+FiEEDNqY
wZ4WGclCdd38J0vOtRc7Rs0FAmIuG8cCGwMFCQPCZwAFCwkIBwIGFQoJCAsCBBYC
AwECHgECF4AACgkQJ0vOtRc7Rs1aKxAAm7eC32VbPzNh4F4wPCXzdLMvaCpIMXHi
RwkH4JZZoBu0eQU16Qko0gj1EQPtRt6fBkA5vnHOPjQr/vLwytPUpeS/b7chJAKV
4FOaabJO5Vfabjg2zo9boAxKzqS7f+biY7f3OwnMxus3utiRhE8gEcSMGt2Sgrrz
vmiRXWMwMJVELAi2rfCjUrGTZzVLeL6jOkKeA9gTnxX4TWb3jtA8EVTFB+lP4Tys
yyKYN9GzWOMCZma3UglBzUNm6i3eoLwFxhbAfIgDmq1Ysun5QOj7gL52keNqgGxP
ZZC9jJAxU+hjiTZzl1qh1z9+KeRqrMsoiKg1n5CdU0utFhNpsOlWfx082fVF/Qxn
wFW2KLb72A/RWloki78DbOybuq5beC3a2CvTRmz615wJmSIW7wAlNc009xds905t
75BRa48EW1v5D05pZi1e58RqFL+MBVCxF+x1BTOv7pe9/W3YI05RbJhZPocDDCjs
pIlSfr3rC58uZBXEKfNoFjkaGqj7eF9j+T/y57i10Q1jcmRGPL7AQgvg3lc3ya+R
ZX9TCKK4FJAAphrwviPvjXaGRgLsanaqLJkQBbGevicDNuP1HR0uHljdVDZj7mdC
kImEHyjeOmUMTVJtZVRD7INaShylGWYE8TRYdOtDSWOPnC5sdz26oaHqwxga9RrB
UiPZ6C0xzaA=
=lE7o
-----END PGP PUBLIC KEY BLOCK-----
```

Import GPG Identity on github.com
-----------------------------
1. In the upper-right corner of any page, click your profile photo, then click Settings.

2. In the "Access" section of the sidebar, click  SSH and GPG keys.

3. Click New GPG key.
![New GPG Key](/images/github-gpg-keys.png 'New GPG Key')

4. In the "Key" field, paste the GPG key you copied when you generated your GPG key.
![Paste GPG Key](/images/github-gpg-key-paste.png 'Paste GPG Key')

5.Click Add GPG key.

6.To confirm the action, enter your GitHub password.

Setup local environment to use this identity
--------------------------------------------
1. In order for GitHub to accept your GPG key and show your commits as “verified”, you first need to ensure that the email address you use when committing a code change is both included in the GPG key and verified on GitHub.
   To set what email address Git uses when creating a commit use:
```shell
$ git config --global user.name "John Doe"
$ git config --global user.email john.doe@example.com
```

2. We are going to set the default git signing key to `274BCEB5173B46CD`. Next we will tell git to automatically sign commits and tags. 
```shell
$ git config --global user.signingkey 274BCEB5173B46CD
$ git config --global tag.gpgSign true
$ git config --global commit.gpgsign true
```
