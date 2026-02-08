# devmail

## NEED ADD INSTALL STREPS.

##Decrypt file save in same file

```
sops --decrypt --in-place  dns_google_domains_credentials.ini
```

##Encrypt file in same file
```
sops -e -i --encrypted-regex '^(.*token)$' dns_google_domains_credentials.ini
```

##Example .sops.yaml :
```
---
creation_rules:
  - path_regex: .*\.ini$
    encrypted_regex: '^(user*|pass*|.*[Bb]earer.*|.*[Kk]ey|.*[Kk]eys|salt|sentry.*|*[Tt]oken)$'
    key_groups:
      - age:
          - age12xe6r5ge6sqpwj4genlmrejtmsfhk6y0674z7r7k8leyy4paupqq7f6swg
```
