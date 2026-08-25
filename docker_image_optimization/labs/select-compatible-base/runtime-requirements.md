# Runtime Requirements

The application requires:

- a Linux image;
- a POSIX-compatible `/bin/sh`;
- no `glibc`-specific native extension;
- no package manager operation after the image is built;
- no interactive debugging shell requirement in production;
- a non-root configured runtime user.

Choose the smallest provided candidate that satisfies all requirements. Do not assume the same choice is correct for an application that requires `glibc` or a vendor-supported Debian package.
